"""แปลง Qwen2.5-1.5B-Instruct เป็น Core ML แบบใช้งานจริงได้

ต่างจากรอบแรกสามข้อ — ทั้งสามข้อจำเป็น ขาดข้อใดข้อหนึ่งโมเดลก็ใช้ในแอปไม่ได้

1. **stateful KV cache** — cache เก็บเป็น Core ML state (`ct.StateType`) โมเดลจำ
   token ที่ผ่านมาได้เอง แต่ละรอบ generate จึงป้อนแค่ token ใหม่ตัวเดียว
   ไม่ใช่ป้อนทั้ง sequence ซ้ำ
2. **ความยาว input ยืดหยุ่น** (`RangeDim`) — prefill ป้อนเป็นก้อนละไม่เกิน
   PREFILL_CHUNK แล้ว decode ป้อนทีละ 1 token
3. **quantize 4-bit** — 2.9 GB → ~1.1 GB ระดับที่ iPhone โหลดไหว

รันบน Colab (CPU runtime ก็พอ) การติดตั้งต้องแยกเป็นสามเซลล์ ห้ามยัดรวมบรรทัดเดียว:

    # เซลล์ 1 — torchvision/torchaudio ที่ Colab ให้มาถูก build มากับ torch 2.11
    # ถ้าไม่ถอนทิ้งจะ import พังตอนเจอ torch 2.4.1 ส่วน --index-url กัน pip
    # ไม่ให้ลาก CUDA build กับ nvidia-* มาอีก ~3 GB ทั้งที่ไม่ได้ใช้
    !pip uninstall -y torchvision torchaudio
    !pip install torch==2.4.1 --index-url https://download.pytorch.org/whl/cpu
    !pip install numpy==1.26.4 transformers==4.44.2 coremltools==8.3 sentencepiece protobuf

    # เซลล์ 2 — บังคับรีสตาร์ท (จะมี ERROR เรื่อง dependency conflict ของ
    # opencv / jax / gradio ฯลฯ โผล่ในเซลล์ 1 — ไม่ต้องสนใจ ไม่ได้อยู่ในเส้นทางนี้)
    import os; os.kill(os.getpid(), 9)

    # เซลล์ 3 — รีสตาร์ทแล้ว Drive หลุด mount ทุกครั้ง ต้อง mount ใหม่ก่อนรันสคริปต์
    from google.colab import drive; drive.mount("/content/drive")

เวอร์ชันต้องตรงตามนี้จริง ๆ ไม่ใช่ "ใกล้เคียงก็พอ":

- `transformers` — คลาส `Cache` ถูกรื้อ API หลายรอบ รุ่นใหม่บังคับให้ส่ง `layers`
  ตอนสร้าง และเปลี่ยนวิธีส่ง attention mask ทำให้ trace ไม่ผ่าน
- `coremltools` — ต้อง 8 ขึ้นไปถึงจะมี stateful model กับ int4
- `torch` — coremltools 8.3 รองรับถึงราว 2.5 เท่านั้น ตัวที่ Colab ให้มาใหม่กว่านั้น

โมเดลที่ได้ต้อง `minimum_deployment_target=iOS18` เป็นอย่างต่ำ — state กับ int4
เป็นของใหม่ใน iOS 18 ทั้งคู่

WARNING ชุด `Failed to load _MLModelProxy: No module named coremltools.libcoremlpython`
กับ `Torch var keyCache is added again` เป็นของปกติ อันแรกคือ Linux ไม่มี Core ML
runtime อันหลังคือ state ถูกอ้างถึงหลายจุดในกราฟ ทั้งคู่ไม่กระทบผลลัพธ์

── สัญญาการเรียกใช้ฝั่ง Swift ──────────────────────────────────────────────

    input_ids    (1, q)           int32    q อยู่ในช่วง 1..PREFILL_CHUNK
    causal_mask  (1, 1, q, ctx)   fp16     ctx อยู่ในช่วง 1..MAX_CONTEXT
    logits       (1, 1, 151936)   fp16     เฉพาะตำแหน่งสุดท้ายเท่านั้น
    keyCache / valueCache         state    ผูกกับ MLState ไม่ต้องส่งเข้า-ออกเอง

โมเดลอนุมาน "จำนวน token ที่อยู่ใน cache แล้ว" จาก `ctx - q` ไม่ได้รับเป็น input
ดังนั้น mask ต้องกว้างเท่ากับจำนวน token ทั้งหมดที่มองเห็นได้ ไม่ใช่แค่ก้อนปัจจุบัน

prefill เป็นก้อน:

    past = 0
    for chunk in promptTokens.chunked(into: PREFILL_CHUNK) {
        ctx = past + chunk.count
        // mask (1, 1, chunk.count, ctx) — แถว i คอลัมน์ j
        //   j <= past + i  ->  0
        //   นอกนั้น        ->  -65504 (ค่าต่ำสุดของ fp16)
        // คอลัมน์ 0..<past เป็นของ token เก่าใน cache เปิดหมดทุกแถว
        // ที่ต้อง mask มีแค่สามเหลี่ยมบนภายในก้อนปัจจุบัน
        predict(chunk, mask, state)
        past += chunk.count
    }

decode ทีละ token: q = 1, ctx = past + 1, mask เป็นศูนย์ทั้งแถว (มองเห็นได้หมด)

ถ้า system prompt ยาวและใช้ซ้ำทุกเทิร์น ให้ prefill ครั้งเดียวแล้วถือ MLState
ตัวเดิมไว้ อย่าสร้างใหม่ทุกข้อความ — นั่นคือเหตุผลทั้งหมดที่ทำ stateful

── กับดักที่เสียเวลาไปแล้วรอบละครั้ง ───────────────────────────────────────

`AttributeError: 'list' object has no attribute 'val'` ตอนเรียก get_weights_metadata
    บั๊กของ coremltools 8.3 เอง มันวน `child_op.inputs.items()` แล้วสะดุด op ที่
    รับ input เป็น list เช่น `concat` ไม่เกี่ยวกับโมเดล เลี่ยงด้วยการเดิน
    protobuf ของ spec เองใน find_const_names()

โมเดลแปลงผ่าน ไม่มี error แต่พ่นข้อความไร้ความหมาย
    ตาราง cos/sin ของ RoPE ถูก quantize ไปด้วย ดูคอมเมนต์ยาวที่ rope_consts
    ข้างล่าง อาการเฉพาะตัวคือ **ป้อน token เดียวยังพอได้ เกินหนึ่งพังทันที**
    ถ้าเจออาการนี้อีกให้สงสัย const ที่เก็บค่าต่อเนื่องช่วงแคบก่อนเสมอ
    ไม่ใช่ตัว weight ของ layer



`NotImplementedError: Make sure to implement get_max_length in a subclass`
    transformers 4.44 ประกาศ `get_max_length()` ไว้เป็น abstract ใน `Cache`
    attention เรียกผ่าน `get_usable_length()` subclass จึงต้อง implement เอง

`AssertionError: tensor value not consistent between torch ir and state_dict`
    สองสาเหตุรวมกัน — (ก) `torch.jit.trace` รัน forward จริงหนึ่งรอบ cache จึงมี
    ค่า K/V ของ dummy input ค้างอยู่ ต่างจากค่าที่กราฟจับไว้ ต้อง `.zero_()`
    หลัง trace  (ข) transformers 4.44 ทำให้ `Cache` สืบทอด `nn.Module` ถ้าเก็บ
    cache เป็น attribute ตรง ๆ มันจะถูกจดเป็น submodule แล้ว tensor ก้อนเดียว
    จะเข้าถึงได้สองชื่อ (`keyCache` กับ `kv_cache.k`) — เลี่ยงด้วย
    `object.__setattr__` ให้ buffer เป็นเจ้าของ tensor ส่วน cache แค่ยืมไปใช้
    ตัวอย่างของ Apple ไม่เจอทั้งสองข้อเพราะรุ่นที่เขาใช้ `Cache` ยังเป็นคลาสธรรมดา

`ValueError: compression config conflict detected between ops ... gather ... linear`
    Qwen2.5-1.5B ตั้ง `tie_word_embeddings: true` — embedding table กับ lm_head
    เป็น const ก้อนเดียวกัน ป้อนทั้ง op `gather` และ op `linear` การสั่งให้
    `gather` ข้าม quantize แต่ `linear` ไม่ข้าม = สั่งให้ const ก้อนเดียวมี
    สองนโยบาย ซึ่งทำไม่ได้ ดู EMBEDDING_POLICY ข้างล่าง

── เรื่อง RAM ─────────────────────────────────────────────────────────────
Colab ฟรีให้ราว 12.7 GB ซึ่งเฉียดกับที่งานนี้ใช้ สคริปต์จึงเซฟ fp16 ลงดิสก์
ก่อนเข้าขั้น quantize และตรวจหาไฟล์นั้นตอนเริ่ม ถ้าเซสชันตายกลางทาง
(อาการคือหลุดเงียบ ๆ ไม่มี traceback = OOM) ให้ Restart session แล้วรันไฟล์นี้ซ้ำ
มันจะข้าม trace/convert ไปทำต่อจาก fp16 ที่มีอยู่ในเซสชันสะอาด ซึ่งใช้ RAM
แค่ครึ่งเดียว — /content ไม่ถูกล้างตอน restart จะหายก็ต่อเมื่อ disconnect

ชื่อ checkpoint ผูกกับ EMBEDDING_POLICY, MAX_CONTEXT และ PREFILL_CHUNK
เปลี่ยนค่าไหนก็ได้ไฟล์ใหม่อัตโนมัติ ไม่มีทางเผลอหยิบของเก่ามาใช้ผิดรุ่น
"""

import gc
import os
import shutil
from pathlib import Path

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


# ── เช็กทุกอย่างก่อนทำอะไรทั้งสิ้น ─────────────────────────────────────────
#
# เช็กตรงนี้เพราะถ้าปล่อยผ่านไป จะไปพังตอนสร้าง cache ซึ่งอยู่หลังโหลดโมเดล 3 GB
# เสียเวลาฟรีหลายนาทีต่อรอบ — ที่แย่กว่านั้นคือ Drive ซึ่งเดิมไปพังตอน copy
# บรรทัดรองสุดท้าย หลังงานหนักเสร็จหมดแล้ว
def _require(module, expected):
    import importlib

    actual = importlib.import_module(module).__version__
    if not actual.startswith(expected):
        raise SystemExit(
            f"{module} เป็น {actual} แต่ต้องการ {expected}.x\n"
            "ติดตั้งตามสามเซลล์ใน docstring ด้านบน แล้ว Restart session ก่อนรันใหม่"
        )


_require("transformers", "4.44")
_require("torch", "2.4")
_require("coremltools", "8.")

if not os.path.isdir("/content/drive/MyDrive"):
    raise SystemExit(
        "Drive ยังไม่ถูก mount — การ Restart session ทำให้ mount หลุดทุกครั้ง\n"
        "รัน: from google.colab import drive; drive.mount('/content/drive')"
    )

MODEL_NAME = "Qwen/Qwen2.5-1.5B-Instruct"
# OUTPUT_PATH กับ DRIVE_ZIP_PATH ตั้งทีหลัง หลังรู้ค่า QUANT_DTYPE แล้ว

# ── งบ token ────────────────────────────────────────────────────────────────
#
# MAX_CONTEXT คือ prompt + คำตอบ + chat template รวมกัน ไม่ใช่แค่ prompt
# ตั้งไว้ 2304 = prompt 2000 + คำตอบ ~150 + template ของ Qwen2.5 (im_start /
# im_end สามบล็อก) ~20 + เผื่ออีกหน่อย
#
# cache กิน 28 KB ต่อ token (28 layer x 2 kv head x 128 x 2 byte x 2 ก้อน K/V)
# ที่ 2304 คือราว 66 MB ตัวไฟล์โมเดลไม่โตขึ้นเลย เพราะ state เป็นบัฟเฟอร์
# ที่ allocate ตอนรัน ไม่ได้เก็บลง .mlpackage
MAX_CONTEXT = 2304

# เพดาน token ต่อการเรียกหนึ่งครั้ง แยกจาก MAX_CONTEXT โดยตั้งใจ
#
# ถ้าปล่อยให้ query ยาวได้เท่า context กราฟจะต้องรองรับ prefill 2304 token
# รวดเดียว ซึ่ง attention จะสร้างเมทริกซ์ 12 head x 2304 x 2304 x 2 byte
# = 127 MB ต่อ layer ในหนึ่งครั้ง หนักเกินไปสำหรับ ANE
#
# ที่ 128 เหลือ 12 x 128 x 2304 x 2 = 7 MB ต่อ layer แลกกับการเรียก 16 ครั้ง
# แทนครั้งเดียว ซึ่งรวมแล้วเร็วกว่าเพราะไม่ต้องไปแตะ swap
# 256 ก็ยังไหว (เมทริกซ์โตเป็นสองเท่า เรียกครึ่งเดียว) เกินกว่านั้นไม่คุ้ม
PREFILL_CHUNK = 128

# ── นโยบายเรื่อง embedding table ────────────────────────────────────────────
#
# Qwen2.5-1.5B tie embedding กับ lm_head ไว้เป็น tensor ก้อนเดียว (151936 x 1536
# = ~15% ของพารามิเตอร์) coremltools บังคับให้ const ก้อนเดียวมีนโยบายเดียว
# จึงเลือกได้แค่สองทาง — "เว้น embedding แต่ quantize lm_head" ไม่มีอยู่จริง
# ถ้าไม่แยกสองก้อนออกจากกันก่อน
#
#   "all"   — quantize ทุกอย่างรวม embedding ได้ราว 1.0-1.1 GB ใช้ RAM น้อยสุด
#             เริ่มจากอันนี้ก่อนเสมอ แล้วค่อยวัดคุณภาพ
#   "untie" — clone lm_head ออกมาเป็นก้อนแยก แล้วเว้น embedding ไว้ที่ fp16
#             ได้ราว 1.35 GB และใช้ RAM ตอน trace/convert เพิ่มอีก ~470 MB
#             ใช้เมื่อทดสอบแล้วโมเดลตอบเพี้ยนจนรับไม่ได้
EMBEDDING_POLICY = "all"

# ── ความละเอียดของ quantize ────────────────────────────────────────────────
#
#   "int4"  — ~0.85 GB เป้าหมายที่อยากได้
#   "int8"  — ~1.6 GB ใช้แยกว่าอาการพังมาจากความละเอียดหรือมาจากขั้นแปลง
#   None    — ข้าม quantize ทั้งขั้น ได้ fp16 ~3 GB ใหญ่เกินจะลงเครื่องจริง
#             แต่เป็นค่าอ้างอิงที่เชื่อได้ว่ากราฟถูกหรือผิด
#
# ลำดับที่ควรไล่เมื่อโมเดลตอบไม่รู้เรื่อง: int8 ก่อน ถ้า int8 ดีแปลว่าเป็นเรื่อง
# ความละเอียดล้วน ๆ ถ้า int8 ก็พังเหมือนกันแปลว่าปัญหาอยู่ที่ขั้นแปลง ไม่ใช่ quantize
# — กรณีหลังอย่าเสียเวลาไล่ปรับ block_size ต่อ
QUANT_DTYPE = "int4"

if QUANT_DTYPE not in ("int4", "int8", None):
    raise SystemExit('QUANT_DTYPE ต้องเป็น "int4", "int8" หรือ None')
if EMBEDDING_POLICY not in ("all", "untie"):
    raise SystemExit('EMBEDDING_POLICY ต้องเป็น "all" หรือ "untie" เท่านั้น')
if PREFILL_CHUNK > MAX_CONTEXT:
    raise SystemExit("PREFILL_CHUNK ห้ามเกิน MAX_CONTEXT")

UNTIE_LM_HEAD = EMBEDDING_POLICY == "untie"

# ใส่ dtype ไว้ในชื่อไฟล์ผลลัพธ์ เพราะช่วงไล่หาสาเหตุจะมีหลายรุ่นปนกันใน Drive
# แล้วแยกไม่ออกว่าอันไหนคืออันไหน
TAG = QUANT_DTYPE or "fp16"
OUTPUT_NAME = f"Qwen-{TAG}.mlpackage"
OUTPUT_PATH = f"/content/{OUTPUT_NAME}"
DRIVE_ZIP_PATH = f"/content/drive/MyDrive/{OUTPUT_NAME}.zip"
FP16_PATH = (
    f"/content/Qwen-fp16-{'untied' if UNTIE_LM_HEAD else 'tied'}"
    f"-c{MAX_CONTEXT}-q{PREFILL_CHUNK}.mlpackage"
)


# ── KV cache ที่เขียนทับตัวเองแบบ in-place ────────────────────────────────
#
# Core ML แปลงการ assign ลง buffer เป็น `slice_update` ให้ ซึ่งเป็น op เดียวที่
# ทำงานกับ state ได้ ห้ามใช้ torch.cat ต่อ cache แบบที่ transformers ทำปกติ
# เพราะจะได้ tensor ใหม่ทุกรอบ — state ไม่ถูกเขียนกลับ
#
# คลาสนี้ไม่สร้าง tensor เอง แต่รับ k/v ที่ StatefulQwen จดเป็น buffer ไว้แล้ว
# เจ้าของ tensor จึงมีที่เดียว ไม่เกิดสองชื่อในลำดับชั้นโมดูล
class SliceUpdateKeyValueCache(Cache):
    def __init__(self, *, k, v, max_context):
        super().__init__()
        self.past_seen_tokens = 0
        # เก็บเป็น Python int ห้ามไปอ่าน self.k.shape[-2] ทีหลัง เพราะ self.k
        # ถูก trace ค่าที่ได้จะกลายเป็น traced value แล้วการเปรียบเทียบใน
        # get_usable_length() จะงอกเข้าไปในกราฟโดยเปล่าประโยชน์
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

    # transformers 4.44 ประกาศเมธอดนี้ไว้เป็น abstract — attention เรียกผ่าน
    # get_usable_length() ทำให้ trace ตายด้วย NotImplementedError ถ้าไม่ implement
    def get_max_length(self):
        return self.max_context

    # ชื่อที่ transformers รุ่นหลังเปลี่ยนไปใช้ ใส่ไว้กันเหนียว
    def get_max_cache_shape(self):
        return self.max_context


class StatefulQwen(torch.nn.Module):
    """ห่อ Qwen ให้รับ causal mask ตรงๆ และอัปเดต cache เอง

    `past_seen_tokens` คำนวณจาก *รูปร่าง* ของ input ไม่ใช่จากค่าใน tensor —
    ตรงนี้สำคัญ เพราะตอน trace ค่าจริงยังไม่มี แต่รูปร่างเป็นสัญลักษณ์ที่
    coremltools คำนวณต่อได้ ทำให้ได้กราฟเดียวที่ใช้ได้ทั้ง prefill และ decode
    และเป็นเหตุผลที่ prefill แบ่งเป็นก้อนได้โดยไม่ต้องแปลงโมเดลใหม่
    """

    def __init__(self, model, max_context):
        super().__init__()
        self.model = model
        self.model.model.config.use_cache = True

        cfg = model.config
        head_dim = getattr(cfg, "head_dim", None) or (
            cfg.hidden_size // cfg.num_attention_heads
        )
        dtype = next(model.parameters()).dtype
        self.cache_shape = (
            cfg.num_hidden_layers,
            1,
            cfg.num_key_value_heads,
            max_context,
            head_dim,
        )

        # buffer เป็นเจ้าของ tensor แต่ผู้เดียว ชื่อสองอันนี้ต้องตรงกับ
        # ct.StateType(name=...) ตอน convert และตรงกับที่ฝั่ง Swift เรียกใช้
        self.register_buffer("keyCache", torch.zeros(self.cache_shape, dtype=dtype))
        self.register_buffer("valueCache", torch.zeros(self.cache_shape, dtype=dtype))

        # object.__setattr__ ข้าม nn.Module.__setattr__ ไปเลย ทำให้ kv_cache
        # ไม่ถูกจดใน _modules — ไม่งั้น (เพราะ Cache สืบทอด nn.Module ตั้งแต่
        # transformers 4.41) tensor ก้อนเดียวจะเข้าถึงได้ทั้งทาง keyCache และ
        # ทาง kv_cache.k ซึ่งทำให้ coremltools เทียบ IR กับ state_dict ไม่ตรง
        object.__setattr__(
            self,
            "kv_cache",
            SliceUpdateKeyValueCache(
                k=self.keyCache, v=self.valueCache, max_context=max_context
            ),
        )

    def forward(self, input_ids, causal_mask):
        # ความยาวคอลัมน์ของ mask = จำนวน token ทั้งหมดที่มองเห็นได้
        # ลบด้วยจำนวน token ที่ป้อนเข้ามารอบนี้ = จำนวนที่อยู่ใน cache อยู่แล้ว
        self.kv_cache.past_seen_tokens = causal_mask.shape[-1] - input_ids.shape[-1]
        logits = self.model(
            input_ids=input_ids,
            attention_mask=causal_mask,
            past_key_values=self.kv_cache,
            use_cache=True,
        ).logits
        # คืนเฉพาะตำแหน่งสุดท้าย — ที่ generate ต้องใช้มีแค่นี้ ถ้าคืนทั้งก้อน
        # prefill ก้อนละ 128 token จะได้ output 128 x 151936 x 2 = 39 MB ทิ้งเปล่า
        # ทุกก้อน ตัดแล้วเหลือ 0.3 MB คงที่ทั้ง prefill และ decode
        #
        # >>> ฝั่ง Swift ต้องอ่าน output เป็น shape (1, 1, 151936) ไม่ใช่ (1, q, 151936)
        return logits[:, -1:, :]


# ── สร้างโมเดล fp16 (ข้ามได้ถ้าเคยทำสำเร็จแล้ว) ─────────────────────────────
print(
    f"policy={EMBEDDING_POLICY}  MAX_CONTEXT={MAX_CONTEXT}  "
    f"PREFILL_CHUNK={PREFILL_CHUNK}"
)
print(f"checkpoint -> {FP16_PATH}")

if os.path.isdir(FP16_PATH):
    print("พบ checkpoint อยู่แล้ว — ข้าม trace/convert ไปทำ quantize ต่อ")
    mlmodel = ct.models.MLModel(FP16_PATH, skip_model_load=True)
else:
    print("Loading model...")
    torch_model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True,
        attn_implementation="eager",
    )
    torch_model.eval()

    if UNTIE_LM_HEAD:
        # clone ให้ lm_head มี storage ของตัวเอง const ในกราฟจะแยกเป็นสองก้อน
        # แล้ว op_type_configs ถึงจะสั่ง gather กับ linear คนละอย่างได้
        print("Untying lm_head from embed_tokens...")
        torch_model.lm_head.weight = torch.nn.Parameter(
            torch_model.lm_head.weight.detach().clone()
        )
        torch_model.config.tie_word_embeddings = False

    wrapper = StatefulQwen(torch_model, MAX_CONTEXT).eval()
    cache_shape = wrapper.cache_shape  # เก็บไว้ก่อน del wrapper
    cache_mb = cache_shape[0] * cache_shape[2] * cache_shape[3] * cache_shape[4] * 2 * 2 / 1e6
    print(f"cache shape: {cache_shape}  (~{cache_mb:.0f} MB ตอนรันบนเครื่อง)")

    # ตัวอย่างสำหรับ trace: ป้อน 2 token โดยมีของเก่าใน cache อยู่แล้ว 1 token
    # ต้องให้ทั้งสองมิติต่างกัน ไม่งั้น trace จะยุบสองค่านี้เป็นตัวเดียว
    # ค่าเล็กแบบนี้ใช้ได้กับทุก MAX_CONTEXT เพราะกราฟอ้างอิงรูปร่างเชิงสัญลักษณ์
    example_ids = torch.zeros((1, 2), dtype=torch.int32)
    example_mask = torch.zeros((1, 1, 2, 3), dtype=torch.float16)

    # TracerWarning เรื่อง "Converting a tensor to a Python boolean/integer"
    # จะโผล่มาหลายบรรทัดตรงนี้ — ปกติสำหรับดีไซน์นี้ ทุกอันเป็นเรื่องของ shape
    # ไม่ใช่ค่าใน tensor จึงไม่กระทบความถูกต้องของกราฟ
    print("Tracing...")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (example_ids, example_mask))

    # trace รัน forward จริงหนึ่งรอบ cache จึงมีค่า K/V ของ dummy input ค้างอยู่
    # ต้องล้างกลับเป็นศูนย์ให้ตรงกับค่าที่กราฟจับไว้ ไม่งั้น convert จะตายด้วย
    # AssertionError: tensor value not consistent between torch ir and state_dict
    for _m in (wrapper, traced):
        for _n in ("keyCache", "valueCache"):
            _buf = getattr(_m, _n, None)
            if _buf is not None:
                _buf.zero_()

    # เช็คว่ามี tensor ตัวไหนใช้ storage ร่วมกันบ้าง — ถ้า EMBEDDING_POLICY = "all"
    # จะเห็น lm_head แชร์กับ embed_tokens ซึ่งเป็นเรื่องปกติของโมเดลที่ tie ไว้
    _seen = {}
    for _n, _t in list(traced.named_parameters()) + list(traced.named_buffers()):
        if _t.data_ptr() in _seen:
            print(f"SHARED: {_seen[_t.data_ptr()]} <-> {_n}")
        _seen[_t.data_ptr()] = _n
    del _seen

    # del สองบรรทัดนี้ยังไม่คืน RAM จริง เพราะ traced ถือ tensor ชุดเดียวกันอยู่
    # ที่คืนจริงคือ del traced หลัง convert เสร็จ
    del torch_model, wrapper
    gc.collect()

    # query_length = จำนวน token ที่ป้อนรอบนี้ (prefill = ก้อนละไม่เกิน
    # PREFILL_CHUNK, decode = 1) ส่วน context_length = จำนวนที่มองเห็นได้ทั้งหมด
    # สองอันนี้ต้องแยกเพดานกัน ดูเหตุผลที่คอมเมนต์ของ PREFILL_CHUNK
    query_length = ct.RangeDim(lower_bound=1, upper_bound=PREFILL_CHUNK, default=1)
    context_length = ct.RangeDim(lower_bound=1, upper_bound=MAX_CONTEXT, default=1)

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

    # เซฟก่อน quantize แล้วโหลดกลับใหม่ — ได้จุด resume และปล่อย spec ชุดแรก
    # ทิ้งก่อนจะสร้างชุด int4 ซึ่งเป็นช่วงที่ RAM พีคที่สุด
    print(f"Saving fp16 checkpoint to {FP16_PATH} ...")
    mlmodel.save(FP16_PATH)
    del mlmodel
    gc.collect()
    mlmodel = ct.models.MLModel(FP16_PATH, skip_model_load=True)


# ── quantize เหลือ 4 บิต ────────────────────────────────────────────────────
#
# per_block granularity (block 32) เสียคุณภาพน้อยกว่า per_channel ชัดเจนที่
# ระดับ 4 บิต โดยขนาดโตขึ้นแค่ไม่กี่เปอร์เซ็นต์จาก scale ที่ต้องเก็บเพิ่ม
#
# op_type_configs ตั้งได้ต่อเมื่อ untie แล้วเท่านั้น — ตอนที่ยัง tie อยู่
# const ก้อนเดียวป้อนทั้ง gather และ linear การให้คนละ config จะได้
# ValueError: compression config conflict detected
# ── ตาราง RoPE ต้องเว้นไว้ที่ fp16 ห้าม quantize เด็ดขาด ────────────────────
#
# cos/sin cache เป็น const ขนาด [32768, 128] ที่ทั้ง 28 layer ใช้ร่วมกัน
# ค่าอยู่ในช่วง [-1, 1] แบบต่อเนื่อง พอบีบเหลือ int4 (16 ระดับต่อบล็อก) ข้อมูล
# ตำแหน่งก็หายหมด โมเดลยังตอบได้เมื่อป้อน token เดียว (ตำแหน่ง 0 คือ cos=1 sin=0
# ซึ่งรอดจากการปัด) แต่พอเกินหนึ่ง token จะพ่นข้อความไร้ความหมายทันที
#
# อาการนี้หลอกมาก เพราะไม่มี error ให้เห็นสักบรรทัด ทั้ง convert ทั้งตอนรัน
# เจอครั้งแรกตอนรันจริงบนแมค — สังเกตจาก "The capital of France is" แล้วโมเดล
# ไม่ตอบ " Paris"
#
# ยกเว้นสองก้อนนี้แล้วไฟล์โตขึ้นราว 13 MB จากทั้งหมดกว่า 800 MB
def find_const_names(model, needle):
    """คืนชื่อ const ทุกก้อนในกราฟที่ชื่อมี `needle`

    เดินบน protobuf ของ spec เองแทนที่จะใช้ `get_weights_metadata` เพราะตัวนั้น
    พังใน coremltools 8.3 — มันวน `child_op.inputs.items()` แล้วสะดุด op ที่รับ
    input เป็น list (เช่น `concat`) ได้ AttributeError: 'list' object has no
    attribute 'val' ซึ่งไม่เกี่ยวกับโมเดลเราเลย

    ใน MIL ชื่อของ const คือชื่อ output ของมัน
    """
    names = []
    for function in model.get_spec().mlProgram.functions.values():
        for block in function.block_specializations.values():
            for op in block.operations:
                if op.type == "const":
                    names += [o.name for o in op.outputs if needle in o.name]
    return names


if QUANT_DTYPE is None:
    print("ข้าม quantize ทั้งขั้น — เซฟเป็น fp16 ตามที่ตั้ง QUANT_DTYPE = None")
else:
    rope_consts = find_const_names(mlmodel, "rotary_emb")
    if not rope_consts:
        raise SystemExit(
            "หา const ของ RoPE ไม่เจอ — ชื่ออาจเปลี่ยนไปตามรุ่น transformers\n"
            "อย่าปล่อยผ่าน ถ้า quantize ทับตารางนี้โมเดลจะพ่นขยะโดยไม่มี error\n"
            "ลองหาชื่อที่ใกล้เคียงด้วย find_const_names(mlmodel, 'cos') ดูก่อน"
        )
    print(f"Quantizing to {QUANT_DTYPE}...")
    print(f"เว้นไม่ quantize {len(rope_consts)} ก้อน: {rope_consts}")

    quant_config = OptimizationConfig(
        global_config=OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype=QUANT_DTYPE,
            granularity="per_block",
            block_size=32,
        ),
        # embedding lookup ปรากฏเป็น op `gather` — ตั้ง None = ไม่แตะ
        op_type_configs={"gather": None} if UNTIE_LM_HEAD else None,
        op_name_configs={name: None for name in rope_consts},
    )
    mlmodel = linear_quantize_weights(mlmodel, config=quant_config)

print(f"Saving to {OUTPUT_PATH} ...")
mlmodel.save(OUTPUT_PATH)

print("Zipping...")
shutil.make_archive(OUTPUT_PATH, "zip", root_dir="/content", base_dir=OUTPUT_NAME)
shutil.copy(f"{OUTPUT_PATH}.zip", DRIVE_ZIP_PATH)
print(f"copied -> {DRIVE_ZIP_PATH}")

# พิมพ์ signature ไว้เทียบกับฝั่ง Swift — ถ้าชื่อหรือ shape ไม่ตรง แอปจะพังตอนรัน
# วางไว้ท้ายสุดโดยตั้งใจ ของถูกเซฟและ copy ขึ้น Drive ไปแล้วก่อนถึงบรรทัดนี้
# ถ้าตรงนี้พังจึงไม่เสียงาน
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

size_gb = sum(f.stat().st_size for f in Path(OUTPUT_PATH).rglob("*") if f.is_file()) / 1e9
_expected = {"int4": "~0.85 GB", "int8": "~1.6 GB", None: "~3.1 GB"}[QUANT_DTYPE]
if UNTIE_LM_HEAD and QUANT_DTYPE is not None:
    _expected += " + อีกราว 0.4 GB จาก embedding ที่เว้นไว้"
print(f"\nFINISHED — ขนาด {size_gb:.2f} GB (คาดไว้ {_expected})")
print(f"รับได้ {MAX_CONTEXT} token รวม prompt + คำตอบ, ป้อนก้อนละไม่เกิน {PREFILL_CHUNK}")
