"""แปลง Qwen2.5-1.5B-Instruct เป็น Core ML แบบใช้งานจริงได้

ต่างจากรอบแรกสามข้อ — ทั้งสามข้อจำเป็น ขาดข้อใดข้อหนึ่งโมเดลก็ใช้ในแอปไม่ได้

1. **stateful KV cache** — cache เก็บเป็น Core ML state (`ct.StateType`) โมเดลจำ
   token ที่ผ่านมาได้เอง แต่ละรอบ generate จึงป้อนแค่ token ใหม่ตัวเดียว
   ไม่ใช่ป้อนทั้ง sequence ซ้ำ
2. **ความยาว input ยืดหยุ่น** (`RangeDim`) — prefill ป้อน prompt ยาวเท่าไรก็ได้
   ถึง MAX_CONTEXT แล้ว decode ป้อนทีละ 1 token
3. **quantize 4-bit** — 2.9 GB → ~1.1 GB ระดับที่ iPhone โหลดไหว

รันบน Colab (CPU runtime ก็พอ ใช้ RAM สูงสุดราว 12 GB ตอน quantize)

    !pip install -q transformers==4.44.2 torch==2.4.1 coremltools==8.3 numpy==1.26.4

**ติดตั้งเสร็จต้องสั่ง Runtime → Restart session ก่อนรันสคริปต์นี้** ไม่งั้น Python
ยังถือโมดูลรุ่นที่ Colab ติดตั้งมาให้ค้างอยู่ในหน่วยความจำ pip ที่เพิ่งลงไปจะไม่มีผล
สังเกตได้จาก traceback ที่ชี้ไปที่ `/usr/local/lib/python3.12/dist-packages`

เวอร์ชันต้องตรงตามนี้จริง ๆ ไม่ใช่ "ใกล้เคียงก็พอ":

- `transformers` — คลาส `Cache` ถูกรื้อ API หลายรอบ รุ่นใหม่บังคับให้ส่ง `layers`
  ตอนสร้าง และเปลี่ยนวิธีส่ง attention mask ทำให้ trace ไม่ผ่าน
- `coremltools` — ต้อง 8 ขึ้นไปถึงจะมี stateful model กับ int4
- `torch` — coremltools 8.3 รองรับถึงราว 2.5 เท่านั้น ตัวที่ Colab ให้มาใหม่กว่านั้น

โมเดลที่ได้ต้อง `minimum_deployment_target=iOS18` เป็นอย่างต่ำ — state กับ int4
เป็นของใหม่ใน iOS 18 ทั้งคู่
"""

import gc
import shutil

import numpy as np
import torch
import coremltools as ct
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)
from transformers import AutoModelForCausalLM
from transformers.cache_utils import Cache


# ── เช็กเวอร์ชันก่อนทำอะไรทั้งสิ้น ──────────────────────────────────────────
#
# เช็กตรงนี้เพราะถ้าปล่อยผ่านไป จะไปพังตอนสร้าง cache ซึ่งอยู่หลังโหลดโมเดล 3 GB
# เสียเวลาฟรีหลายนาทีต่อรอบ
def _require(module, expected):
    import importlib

    actual = importlib.import_module(module).__version__
    if not actual.startswith(expected):
        raise SystemExit(
            f"{module} เป็น {actual} แต่ต้องการ {expected}.x\n"
            "รัน: !pip install -q transformers==4.44.2 torch==2.4.1 "
            "coremltools==8.3 numpy==1.26.4\n"
            "แล้วสั่ง Runtime -> Restart session ก่อนรันสคริปต์นี้ใหม่"
        )


_require("transformers", "4.44")
_require("torch", "2.4")
_require("coremltools", "8.")

MODEL_NAME = "Qwen/Qwen2.5-1.5B-Instruct"
OUTPUT_PATH = "/content/Qwen.mlpackage"
DRIVE_ZIP_PATH = "/content/drive/MyDrive/Qwen.mlpackage.zip"

# ความยาวบริบทสูงสุด — กินหน่วยความจำ cache เชิงเส้น ที่ 512 คือราว 15 MB
# coach ใช้ prompt ~250 token ตอบ ~150 token จึงพอสบายๆ
MAX_CONTEXT = 512


# ── KV cache ที่เขียนทับตัวเองแบบ in-place ────────────────────────────────
#
# Core ML แปลงการ assign ลง buffer เป็น `slice_update` ให้ ซึ่งเป็น op เดียวที่
# ทำงานกับ state ได้ ห้ามใช้ torch.cat ต่อ cache แบบที่ transformers ทำปกติ
# เพราะจะได้ tensor ใหม่ทุกรอบ — state ไม่ถูกเขียนกลับ
class SliceUpdateKeyValueCache(Cache):
    def __init__(self, *, shape, dtype=torch.float16):
        super().__init__()
        self.past_seen_tokens = 0
        self.k = torch.zeros(shape, dtype=dtype)
        self.v = torch.zeros(shape, dtype=dtype)

    def update(self, k_state, v_state, layer_idx, cache_kwargs=None):
        begin = self.past_seen_tokens
        end = self.past_seen_tokens + k_state.shape[-2]
        self.k[layer_idx, :, :, begin:end, :] = k_state
        self.v[layer_idx, :, :, begin:end, :] = v_state
        return self.k[layer_idx, :, :, :end, :], self.v[layer_idx, :, :, :end, :]

    def get_seq_length(self, layer_idx=0):
        return self.past_seen_tokens


class StatefulQwen(torch.nn.Module):
    """ห่อ Qwen ให้รับ causal mask ตรงๆ และอัปเดต cache เอง

    `past_seen_tokens` คำนวณจาก *รูปร่าง* ของ input ไม่ใช่จากค่าใน tensor —
    ตรงนี้สำคัญ เพราะตอน trace ค่าจริงยังไม่มี แต่รูปร่างเป็นสัญลักษณ์ที่
    coremltools คำนวณต่อได้ ทำให้ได้กราฟเดียวที่ใช้ได้ทั้ง prefill และ decode
    """

    def __init__(self, model, max_context):
        super().__init__()
        self.model = model
        config = model.config
        self.kv_cache = SliceUpdateKeyValueCache(
            shape=(
                config.num_hidden_layers,
                1,
                config.num_key_value_heads,
                max_context,
                config.hidden_size // config.num_attention_heads,
            )
        )
        self.model.model.config.use_cache = True
        self.register_buffer("keyCache", self.kv_cache.k)
        self.register_buffer("valueCache", self.kv_cache.v)

    def forward(self, input_ids, causal_mask):
        # ความยาวคอลัมน์ของ mask = จำนวน token ทั้งหมดที่มองเห็นได้
        # ลบด้วยจำนวน token ที่ป้อนเข้ามารอบนี้ = จำนวนที่อยู่ใน cache อยู่แล้ว
        self.kv_cache.past_seen_tokens = causal_mask.shape[-1] - input_ids.shape[-1]
        return self.model(
            input_ids=input_ids,
            attention_mask=causal_mask,
            past_key_values=self.kv_cache,
            use_cache=True,
        ).logits


print("Loading model...")
torch_model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16,
    low_cpu_mem_usage=True,
    attn_implementation="eager",
)
torch_model.eval()

wrapper = StatefulQwen(torch_model, MAX_CONTEXT).eval()

# ตัวอย่างสำหรับ trace: ป้อน 2 token โดยมีของเก่าใน cache อยู่แล้ว 1 token
# ต้องให้ทั้งสองมิติต่างกัน ไม่งั้น trace จะยุบสองค่านี้เป็นตัวเดียว
example_ids = torch.zeros((1, 2), dtype=torch.int32)
example_mask = torch.zeros((1, 1, 2, 3), dtype=torch.float16)

print("Tracing...")
with torch.no_grad():
    traced = torch.jit.trace(wrapper, (example_ids, example_mask))

del torch_model, wrapper
gc.collect()

# มิติที่ยืดหยุ่นได้ — query_length คือจำนวน token ที่ป้อนรอบนี้ (prefill = ทั้ง
# prompt, decode = 1) ส่วน context_length คือจำนวนที่มองเห็นได้ทั้งหมด
query_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_CONTEXT, default=1)
context_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_CONTEXT, default=1)

cache_shape = (
    28,  # num_hidden_layers ของ Qwen2.5-1.5B
    1,
    2,  # num_key_value_heads (GQA)
    MAX_CONTEXT,
    128,  # head_dim = 1536 / 12
)

print("Converting to Core ML...")
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, query_length), dtype=np.int32),
        ct.TensorType(
            name="causal_mask",
            shape=(1, 1, query_length, context_length),
            dtype=np.float16,
        ),
    ],
    outputs=[ct.TensorType(name="logits", dtype=np.float16)],
    states=[
        ct.StateType(
            wrapped_type=ct.TensorType(shape=cache_shape, dtype=np.float16),
            name="keyCache",
        ),
        ct.StateType(
            wrapped_type=ct.TensorType(shape=cache_shape, dtype=np.float16),
            name="valueCache",
        ),
    ],
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT16,
    skip_model_load=True,  # เครื่อง Colab เป็น Linux โหลดโมเดล Core ML ไม่ได้
)

del traced
gc.collect()

# ── quantize เหลือ 4 บิต ────────────────────────────────────────────────────
#
# per_block granularity (block 32) เสียคุณภาพน้อยกว่า per_channel ชัดเจนที่
# ระดับ 4 บิต โดยขนาดโตขึ้นแค่ไม่กี่เปอร์เซ็นต์จาก scale ที่ต้องเก็บเพิ่ม
print("Quantizing to 4-bit...")
mlmodel = linear_quantize_weights(
    mlmodel,
    config=OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype="int4",
            granularity="per_block",
            block_size=32,
        )
    ),
)

print(f"Saving to {OUTPUT_PATH} ...")
mlmodel.save(OUTPUT_PATH)

print("Zipping...")
shutil.make_archive("/content/Qwen.mlpackage", "zip", root_dir="/content", base_dir="Qwen.mlpackage")
shutil.copy("/content/Qwen.mlpackage.zip", DRIVE_ZIP_PATH)

# พิมพ์ signature ไว้เทียบกับฝั่ง Swift — ถ้าชื่อหรือ shape ไม่ตรง แอปจะพังตอนรัน
spec = ct.models.utils.load_spec(OUTPUT_PATH)
print("\n=== INPUTS ===")
for i in spec.description.input:
    print(i)
print("=== STATES ===")
for s in spec.description.state:
    print(s)
print("=== OUTPUTS ===")
for o in spec.description.output:
    print(o)

print("\nFINISHED — คาดว่าได้ราว 1.1 GB ถ้าใหญ่กว่า 1.5 GB แปลว่า quantize ไม่ติด")
