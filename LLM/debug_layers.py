"""ทดสอบว่าหลาย layer ใช้ state ก้อนเดียวกันแล้วเหยียบกันเองหรือไม่

── ที่ตัดออกไปแล้วทั้งหมด ──────────────────────────────────────────────────

quantize          int8 พังเท่า int4 เป๊ะ — น้ำหนักชุดเดียวกันให้ผลต่างกันเองได้
                  ตามจำนวน token ที่ป้อน quantize อธิบายไม่ได้
mask              ลองครบทั้ง causal / เปิดหมด / สลับแกน / ไม่รวมตัวเอง และค่าปิด
                  ตั้งแต่ -50 ถึง -65504 ไม่มีแบบไหนทำให้ผลตรง
tokenizer         id ตรงกับ HF เป๊ะ
NaN ในน้ำหนัก     สแกน fp16 blob ครบ 343 ก้อน ไม่เจอสักตัว
ตาราง RoPE        ค่าอยู่ใน [-1, 1] แถวแรก cos=1 sin=0 ถูกต้อง (เคยโดน quantize
                  ทับ แก้ไปแล้ว เป็นบั๊กจริงแต่ไม่ใช่บั๊กเดียว)
ตรรกะ PyTorch     wrapper ให้ผลตรงกับ transformers เป๊ะ ต่าง 0.0000
Q/K หลัง RoPE     ตรงกับ PyTorch ทุกรูปร่าง คลาดเคลื่อนแค่ระดับ fp16
attention 1 ชั้น  `attn_out` ของ layer 0 ตรงกับ PyTorch ทุกเคส รวมทั้ง ctx >= 2
                  — cache หนึ่งชั้นอ่านเขียนถูกต้อง

── สิ่งที่เหลือ ───────────────────────────────────────────────────────────

โมเดลจริงมี 28 layer ที่ใช้ **state ก้อนเดียวกัน** แยกกันด้วย `layer_idx`
ในกราฟจึงกลายเป็น read → slice_update → write_state ต่อกันเป็นลูกโซ่ 28 รอบ
บน state ตัวเดิม ถ้า Core ML ไม่รับประกันลำดับระหว่าง write_state กับ read_state
ที่ตามมา layer หลัง ๆ จะอ่านของเก่าหรือเหยียบของกันเอง — probe ชั้นเดียวไม่มีทาง
เจอเพราะไม่มีชั้นที่สองให้ชน

ไฟล์นี้เอา attention สองชั้นแรกมาต่อกันจริง ๆ ใช้ cache ก้อนเดียวกัน แล้วเทียบ
ผลกับ PyTorch — ถ้าชั้นเดียวถูกแต่สองชั้นผิด ก็ปิดเคสได้

ตัด MLP ออกเพราะไม่เกี่ยวกับ state และกินที่เกือบทั้งหมด (เหลือ ~22 MB แทน 184 MB)

    !python /content/debug_layers.py

ได้สองไฟล์ ส่งกลับมาทั้งคู่
    /content/layers_debug.mlpackage
    /content/layers_reference.npz
"""

import numpy as np
import torch
import coremltools as ct
from transformers import AutoModelForCausalLM
from transformers.cache_utils import Cache

MODEL_NAME = "Qwen/Qwen2.5-1.5B-Instruct"
MAX_CONTEXT = 2304
PREFILL_CHUNK = 128
N_LAYERS = 2  # สองชั้นก็พอพิสูจน์ ถ้าอยากไล่ต่อค่อยเพิ่ม

print("Loading model...")
full = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16,
    low_cpu_mem_usage=True,
    attn_implementation="eager",
)
full.eval()

hidden_size = full.config.hidden_size
n_kv = full.config.num_key_value_heads
head_dim = hidden_size // full.config.num_attention_heads


class SliceUpdateKeyValueCache(Cache):
    """ตัวเดียวกับใน convert.py ทุกบรรทัด"""

    def __init__(self, *, k, v, max_context):
        super().__init__()
        self.past_seen_tokens = 0
        self.max_context = max_context
        self.k = k
        self.v = v

    def update(self, k_state, v_state, layer_idx, cache_kwargs=None):
        begin = self.past_seen_tokens
        end = self.past_seen_tokens + k_state.shape[-2]
        self.k[layer_idx, :, :, begin:end, :] = k_state
        self.v[layer_idx, :, :, begin:end, :] = v_state
        return self.k[layer_idx, :, :, :end, :], self.v[layer_idx, :, :, :end, :]

    def get_seq_length(self, layer_idx=0):
        return self.past_seen_tokens

    def get_max_length(self):
        return self.max_context

    def get_max_cache_shape(self):
        return self.max_context


class LayerStack(torch.nn.Module):
    """attention N ชั้นแรกต่อกัน ใช้ cache ก้อนเดียวกันแยกด้วย layer_idx

    เหมือนโมเดลจริงตรงที่ state เป็นก้อนเดียว มิติแรกคือชั้น — ต่างจาก probe
    ชั้นเดียวที่ไม่มีทางเกิดการเหยียบกันระหว่างชั้น
    """

    def __init__(self, layers, max_context):
        super().__init__()
        self.attns = torch.nn.ModuleList([layer.self_attn for layer in layers])
        cache_shape = (len(layers), 1, n_kv, max_context, head_dim)
        self.register_buffer("keyCache", torch.zeros(cache_shape, dtype=torch.float16))
        self.register_buffer("valueCache", torch.zeros(cache_shape, dtype=torch.float16))
        object.__setattr__(
            self,
            "kv_cache",
            SliceUpdateKeyValueCache(
                k=self.keyCache, v=self.valueCache, max_context=max_context
            ),
        )

    def forward(self, hidden, causal_mask):
        q_len = hidden.shape[1]
        past = causal_mask.shape[-1] - q_len
        self.kv_cache.past_seen_tokens = past
        position_ids = torch.arange(past, past + q_len).unsqueeze(0)

        for attn in self.attns:
            hidden = attn(
                hidden_states=hidden,
                attention_mask=causal_mask,
                position_ids=position_ids,
                past_key_value=self.kv_cache,
                use_cache=True,
            )[0]
        return hidden


probe = LayerStack(full.model.layers[:N_LAYERS], MAX_CONTEXT).eval()

# ── ค่าอ้างอิงจาก PyTorch ──────────────────────────────────────────────────
torch.manual_seed(0)
reference = {}
CASES = [(1, 1), (1, 2), (2, 2), (2, 3), (3, 3), (4, 4)]

for q_len, ctx in CASES:
    hidden = torch.randn(1, q_len, hidden_size, dtype=torch.float16)
    mask = torch.zeros(1, 1, q_len, ctx, dtype=torch.float16)
    probe.keyCache.zero_()
    probe.valueCache.zero_()
    with torch.no_grad():
        out = probe(hidden, mask)
    if torch.isnan(out).any():
        raise SystemExit(f"q{q_len}_ctx{ctx} เป็น NaN ตั้งแต่ใน PyTorch — หยุดก่อน")

    tag = f"q{q_len}_ctx{ctx}"
    # .copy() สำคัญ — numpy ใช้หน่วยความจำร่วมกับ torch ถ้าไม่ก๊อป ค่าที่เก็บไว้
    # จะถูกเขียนทับตอน zero_() รอบถัดไป (เคยพลาดมาแล้วใน debug_rope.py
    # ทำให้อ่านผลผิดไปหนึ่งรอบเต็ม ๆ)
    reference[f"{tag}_hidden"] = hidden.numpy().copy()
    reference[f"{tag}_out"] = out.numpy().copy()
    print(f"{tag}: out{tuple(out.shape)}  |out|max={out.abs().max():.4f}")

np.savez("/content/layers_reference.npz", **reference)
print("\nเซฟ /content/layers_reference.npz แล้ว")

# ── แปลง ───────────────────────────────────────────────────────────────────
example_hidden = torch.randn(1, 2, hidden_size, dtype=torch.float16)
example_mask = torch.zeros(1, 1, 2, 3, dtype=torch.float16)

print("Tracing...")
with torch.no_grad():
    traced = torch.jit.trace(probe, (example_hidden, example_mask))

for _m in (probe, traced):
    for _n in ("keyCache", "valueCache"):
        _buf = getattr(_m, _n, None)
        if _buf is not None:
            _buf.zero_()

query_length = ct.RangeDim(lower_bound=1, upper_bound=PREFILL_CHUNK, default=1)
context_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_CONTEXT, default=1)
cache_shape = (N_LAYERS, 1, n_kv, MAX_CONTEXT, head_dim)

print("Converting...")
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="hidden", shape=(1, query_length, hidden_size), dtype=np.float16),
        ct.TensorType(
            name="causal_mask",
            shape=(1, 1, query_length, context_length),
            dtype=np.float16,
        ),
    ],
    outputs=[ct.TensorType(name="out", dtype=np.float16)],
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
    skip_model_load=True,
)
mlmodel.save("/content/layers_debug.mlpackage")
print("เซฟ /content/layers_debug.mlpackage แล้ว — ส่งกลับมาทั้งสองไฟล์")
