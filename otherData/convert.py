"""แปลง Qwen2.5-1.5B-Instruct เป็น Core ML แบบใช้งานจริงได้

ต่างจากรอบแรกสามข้อ — ทั้งสามข้อจำเป็น ขาดข้อใดข้อหนึ่งโมเดลก็ใช้ในแอปไม่ได้

1. **stateful KV cache** — cache เก็บเป็น Core ML state (`ct.StateType`) โมเดลจำ
   token ที่ผ่านมาได้เอง แต่ละรอบ generate จึงป้อนแค่ token ใหม่ตัวเดียว
   ไม่ใช่ป้อนทั้ง sequence ซ้ำ
2. **รูปร่างตายตัวสองแบบ** (`EnumeratedShapes`) — prefill ก้อนละ PREFILL_CHUNK
   decode ทีละ 1 token ไม่มีมิติที่เปลี่ยนได้เลย
3. **quantize 4-bit** — 3.1 GB → ~0.89 GB ระดับที่ iPhone โหลดไหว

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

    input_ids    (1, q)              int32    q เป็น 1 หรือ PREFILL_CHUNK เท่านั้น
    causal_mask  (1, 1, q, 2304)     fp16     กว้างเต็มเสมอ ไม่ว่าบริบทจะสั้นแค่ไหน
    position_ids (1, q)              int32    ตำแหน่งจริงของแต่ละ token
    logits       (1, 1, 151936)      fp16     เฉพาะตำแหน่งสุดท้าย
    keyCache / valueCache            state    ผูกกับ MLState ไม่ต้องส่งเข้า-ออกเอง

**ไม่มีมิติที่เปลี่ยนได้เลย** — มีแค่สองรูปที่เป็นไปได้ และบอก Core ML ไปตรง ๆ ผ่าน
`EnumeratedShapes` โมเดลจึงไม่ต้องคำนวณขนาดอะไรเองตอนรัน ซึ่งเป็นจุดที่พังมาแล้ว
สองแบบ (ดู FixedShapeKeyValueCache)

`position_ids` เป็นทั้งตำแหน่งของ RoPE และดัชนีที่จะเขียนลง cache — ค่าเดียวกัน
ทั้งสองงาน จึงไม่มีทางเพี้ยนจากกัน

prefill เป็นก้อนละ PREFILL_CHUNK:

    var past = 0
    for chunk in prompt.chunked(into: PREFILL_CHUNK) {
        // ก้อนสุดท้ายมักสั้นกว่า 128 ต้องเติมให้เต็มแล้วปิดส่วนที่เติมด้วย mask
        let padded = chunk + Array(repeating: 0, count: PREFILL_CHUNK - chunk.count)
        let positions = (0..<PREFILL_CHUNK).map { past + $0 }
        // mask (1, 1, 128, 2304) — แถว i คอลัมน์ j
        //   เปิด (0) เมื่อ j <= past + i **และ** i < chunk.count
        //   นอกนั้นปิด (-65504)
        predict(padded, mask, positions, state)
        past += chunk.count
    }

decode: q = 1, positions = [past], mask แถวเดียวเปิดคอลัมน์ 0...past ที่เหลือปิด

**ห้ามแทรกการเรียกรูปร่างอื่นคั่นอีกแล้ว** — วิธีนั้นมีไว้แก้ปัญหา specialization
ค้างของกราฟรุ่นเก่า พอไม่มีมิติที่เปลี่ยนได้ ปัญหานั้นก็หายไป การแทรกจะเหลือแค่
ทำให้ช้าเป็นสองเท่าเปล่า ๆ

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
    — ข้อนี้เป็นบั๊กจริงแต่ไม่ใช่ตัวเดียว ยังมีอีกสองข้อตามมาข้างล่าง

ผลลัพธ์เปลี่ยนไปตาม computeUnits (all / cpuAndGPU ให้คนละคำตอบ)
    เลขล้นใน fp16 — โมเดลที่ถูกต้องต้องให้ผลเท่ากันทุก backend ตัวการคือ
    เลขล้นตอน matmul ของ attention ดู ATTN_SCALE ข้างล่าง

เรียก q=1 ติดกัน สองครั้งแรกถูก ครั้งที่สามเป็นต้นไปผิด
    Core ML ใช้ specialization ที่ cache ไว้ตามรูปร่าง input ทำให้ค่าที่คำนวณ
    จาก shape ค้างอยู่ที่ของเก่า ดู _full_table_rope_forward
    วิธีพิสูจน์: แทรกการเรียกที่รูปร่างต่างกันคั่น แล้วหาย ส่วนรูปร่างเดียวกันไม่ช่วย

`ValueError: State only support fp16 dtype`
    Core ML รับ state เป็น fp16 อย่างเดียว จึงเปลี่ยนไป trace ด้วย fp32 ไม่ได้
    ทั้งที่ fp16 บน CPU ให้ NaN — แต่ไม่ใช่ปัญหาจริง เพราะไฟล์ที่แปลงออกมา
    ไม่มี NaN สักตัว (สแกน fp16 blob ครบ 343 ก้อนแล้ว)

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
import math
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
import transformers.models.qwen2.modeling_qwen2 as qwen2_mod
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
# ตัวหารที่ใช้กัน attention score ล้นใน fp16 — เหตุผลเต็มอยู่ที่ _ScaledMath
# ข้างล่าง ประกาศตรงนี้เพราะชื่อ checkpoint ต้องอ้างถึงมัน
ATTN_SCALE = 64.0

# รูปร่างของตาราง cos/sin ของ RoPE = (max_position_embeddings, head_dim)
# ใช้หาตารางนี้ในกราฟ เพราะหาด้วยชื่อไม่ทนต่อการเปลี่ยนโค้ดฝั่ง PyTorch
ROPE_TABLE_ROWS = 32768
HEAD_DIM = 128

# ชื่อ checkpoint ผูกกับแพตช์ทุกตัวที่มีผลต่อกราฟ (attn64, normfp32, fullrope)
# ของที่ trace ไว้ก่อนแพตช์ใช้ต่อไม่ได้ ถ้าไม่แยกชื่อ สคริปต์จะหยิบของเก่ามา
# quantize เงียบ ๆ แล้วได้ผลพังเหมือนเดิมโดยไม่มีอะไรเตือน
#
# GRAPH_REV เอาไว้กันเคสที่ค่าคงที่ข้างบนไม่เปลี่ยนแต่ *โค้ดที่สร้างกราฟ* เปลี่ยน
# **บวกเลขนี้ทุกครั้งที่แก้ StatefulQwen หรือ FixedShapeKeyValueCache**
# เคยเสียรอบมาแล้วเพราะไม่มีตัวนี้: แก้วิธีเขียน KV cache แล้วรันใหม่ สคริปต์เจอ
# checkpoint ชื่อเดิม เลยข้าม trace/convert ไป quantize ก้อนเก่าซ้ำ ได้ไฟล์ที่
# เหมือนเดิมทุกไบต์ ("พบ checkpoint อยู่แล้ว — ข้าม trace/convert ไปทำ quantize ต่อ")
#
#   rev 2 — เขียน cache ด้วย scatter แบบ functional แล้วเขียนกลับลง state
GRAPH_REV = 2

FP16_PATH = (
    f"/content/Qwen-fp16-attn{ATTN_SCALE:.0f}-normfp32-fullrope-fixedshape"
    f"-{'untied' if UNTIE_LM_HEAD else 'tied'}"
    f"-c{MAX_CONTEXT}-q{PREFILL_CHUNK}-rev{GRAPH_REV}.mlpackage"
)


# ── KV cache ที่เขียนทับตัวเองแบบ in-place ────────────────────────────────
#
# Core ML แปลงการ assign ลง buffer เป็น `slice_update` ให้ ซึ่งเป็น op เดียวที่
# ทำงานกับ state ได้ ห้ามใช้ torch.cat ต่อ cache แบบที่ transformers ทำปกติ
# เพราะจะได้ tensor ใหม่ทุกรอบ — state ไม่ถูกเขียนกลับ
#
# คลาสนี้ไม่สร้าง tensor เอง แต่รับ k/v ที่ StatefulQwen จดเป็น buffer ไว้แล้ว
# เจ้าของ tensor จึงมีที่เดียว ไม่เกิดสองชื่อในลำดับชั้นโมดูล
class FixedShapeKeyValueCache(Cache):
    """cache ที่ไม่มีมิติเปลี่ยนได้และไม่มีเลขคณิตจากรูปร่างเลย

    รุ่นก่อนหน้าเขียนด้วย `self.k[layer, :, :, begin:end, :]` โดย begin/end มาจาก
    `causal_mask.shape[-1] - input_ids.shape[-1]` ซึ่งเป็นเลขที่กราฟต้องคำนวณเอง
    ตอนรัน แล้วพังสองแบบบนของจริง:

      1. Core ML หยิบแผนที่ specialize ตามรูปร่างมาใช้ซ้ำ ค่าที่คำนวณจาก shape จึง
         ค้างที่ของเก่า — decode ก้าวที่สามเป็นต้นไปผิด
      2. บนเครื่องจริง MPSGraph แก้มิติไม่ออกแล้ว assert ตายทั้งโปรเซส
         `Failed to resolve dynamic dimension 3 (got -9223372036854775808)`
         (-9223372036854775808 คือ Int64.min = "ยังไม่ถูกกำหนด")
         เกิดทั้งบน `.all` และ `.cpuAndNeuralEngine` จึงไม่ใช่เรื่อง backend

    รุ่นนี้จึงตัดต้นเหตุทิ้ง:

      * ตำแหน่งที่จะเขียนมาจาก **input** `position_ids` ไม่ใช่จากรูปร่าง
      * เขียนด้วย `scatter_` ซึ่งรับ index เป็น tensor จึงไม่ถูกตรึงตอน trace
        ต่างจากการเฉือนด้วย `begin:end` ที่ตรึงเป็นค่าคงที่
      * **อ่านคืนทั้งก้อน** ไม่เฉือน — ช่องที่ยังไม่ถูกเขียนถูกปิดด้วย mask อยู่แล้ว
        ความยาว key จึงเป็น MAX_CONTEXT ตายตัวเสมอ ไม่มีอะไรให้ resolve

    ราคาที่จ่าย: attention กวาด MAX_CONTEXT ช่องทุกก้าวแม้บริบทจะสั้น แต่แลกกับการ
    ที่ไม่ต้องแทรกการเรียกคั่นเพื่อล้าง specialization อีกแล้ว (เดิมจ่ายสองเท่าอยู่)
    สุทธิจึงไม่ได้แย่ลง
    """

    def __init__(self, *, k, v, max_context):
        super().__init__()
        self.max_context = max_context
        self.k = k
        self.v = v
        # ตั้งจาก forward ก่อนเรียกโมเดล — เป็น tensor ที่มาจาก input ไม่ใช่ค่าคงที่
        self.positions = None

    def update(self, k_state, v_state, layer_idx, cache_kwargs=None):
        # ใช้ `scatter_` ไม่ใช่ `index_copy_` — coremltools ไม่มีตัวแปลงให้ `index_copy_`
        #   RuntimeError: PyTorch convert function for op 'index_copy_' not implemented
        # ทั้งสองตัวทำงานเหมือนกันในกรณีนี้ ต่างแค่ `scatter_` ต้องการ index ที่มีรูปร่าง
        # เท่ากับ source จึงต้องขยายตำแหน่ง (q,) ให้เป็น (1, kv_heads, q, head_dim) ก่อน
        #
        # ขยายด้วย `repeat` (-> `tile` ใน MIL) ไม่ใช่ `expand_as` — `expand` ของ torch
        # เป็น view ที่ stride เป็นศูนย์ ไม่ได้สร้าง tensor จริง coremltools จึงพากราฟ
        # ข้ามการขยายไป เหลือ index รูป (1, 1, q, 1) แล้วไปตายที่ type_inference:
        #   AssertionError  ops/defs/iOS15/scatter_gather.py:429
        #   assert self.data.shape[i] == self.indices.shape[i]
        # (data มี kv_heads = 2 ที่แกน 1 ส่วน index ยังเป็น 1) `tile` วัสดุออกมาเป็น
        # tensor จริง รูปร่างจึงตรงทุกแกนที่ไม่ใช่แกนที่ scatter
        #
        # kv_heads กับ head_dim เป็นค่าคงที่ มีแค่ q ที่เปลี่ยนตาม EnumeratedShapes
        # จึงอ่านจาก k_state ได้โดยไม่ทำให้เกิดเลขที่คำนวณจากรูปร่างเพิ่ม
        index = self.positions.view(1, 1, -1, 1).repeat(
            1, k_state.shape[1], 1, k_state.shape[3]
        )
        #
        # แคสต์ให้ตรงกับ cache ก่อนเขียน — ฝั่ง torch เป็น no-op ตอน dtype ตรงกันอยู่แล้ว
        # แต่ที่ต้องมีเพราะ MIL เข้มกว่า:
        #   ValueError: In op, of type scatter_along_axis, ... the named input `updates`
        #   must have the same data type as the named input `data`. However, updates has
        #   dtype fp16 whereas data has dtype fp32.
        # cache เป็น fp32 ฝั่ง torch (ดูเหตุผลที่ register_buffer) ส่วน k_state มาจาก
        # โมเดล fp16 สองฝั่งจึงไม่ตรงกันในกราฟ ต้องแคสต์ให้ชัด ไม่ใช่ปล่อยให้ frontend เดา
        #
        # ── เขียนลง state ให้ coremltools เห็น ─────────────────────────────────
        #
        # **อย่าเขียนแบบ `self.k[layer_idx].scatter_(...)`** ถึงจะถูกทุกอย่างในสายตา
        # torch แต่ฝั่ง MIL มันคือการเขียนลง *view* แล้วทิ้ง ถ้า `update()` ไปอ่าน
        # `self.k[layer_idx]` กลับมาคืนอีกที ผลของ scatter จะไม่มีใครใช้ coremltools
        # จึงตัดทิ้งทั้งดุ้นเป็น dead code — แปลงผ่าน ไม่มี error สักบรรทัด แต่ได้โมเดลที่
        # cache เป็นศูนย์ตลอด attention มองไม่เห็นแม้แต่ token ของตัวเอง คำตอบจึงเป็น
        # ขยะและ *เหมือนกันทุก prompt* (วัดมาแล้ว 23-35 tok/s เพราะทำงานน้อยลง)
        #
        # ตรวจจับได้ถูก ๆ โดยไม่ต้องรันโมเดล — ดู `_assert_state_writes()` ใต้ ct.convert
        #
        # รุ่นนี้จึงแยกเป็นสองจังหวะให้ชัด: scatter แบบ functional ได้ tensor ก้อนใหม่
        # ออกมาก่อน แล้วค่อยเขียนกลับลง buffer ด้วย `__setitem__` ซึ่งเป็นการเขียนลง
        # ตัว state จริง (แกน 0 เป็นค่าคงที่ตอน trace เพราะ layer_idx เป็น int ธรรมดา)
        # แล้ว **คืนก้อนที่ scatter ออกมา ไม่ใช่อ่าน state กลับ** — กันไม่ให้ผลถูกทิ้งอีก
        k_new = torch.scatter(self.k[layer_idx], 2, index, k_state.to(self.k.dtype))
        v_new = torch.scatter(self.v[layer_idx], 2, index, v_state.to(self.v.dtype))
        self.k[layer_idx] = k_new
        self.v[layer_idx] = v_new
        # แคสต์กลับก่อนคืน — attention เอาไป matmul กับ q ที่เป็น fp16 ถ้าคืน fp32
        # ดิบ ๆ torch จะตายตั้งแต่ตอน trace (`expected scalar type Half but found Float`)
        return k_new.to(k_state.dtype), v_new.to(v_state.dtype)

    def get_seq_length(self, layer_idx=0):
        return 0

    def get_max_length(self):
        return self.max_context

    def get_max_cache_shape(self):
        return self.max_context

    # attention คำนวณ `kv_seq_len = key_states.shape[-2] + get_usable_length(...)`
    # โดยดูจาก cache *ก่อน* อัปเดต แล้วเอาไปตรวจว่า attn_weights ขนาดถูกไหม
    #
    # เราคืน cache ทั้งก้อนเสมอ ความยาว key จึงเป็น max_context ไม่ใช่ความยาวก้อนที่
    # ป้อนเข้ามา ถ้าไม่บอกตรงนี้จะตกการตรวจทันที:
    #   Attention weights should be of size (1, 12, 128, 128), but is (1, 12, 128, 2304)
    #
    # และค่านี้ยังเป็นตัวที่ attention ใช้ตรวจขนาด mask ด้วย ซึ่ง mask ของเราก็กว้าง
    # max_context เต็มเสมอ จึงตรงกันพอดีทั้งสองจุด
    def get_usable_length(self, new_seq_length, layer_idx=0):
        return self.max_context - new_seq_length


# ── RMSNorm: เคยแก้ด้วยการขยับสเกลแล้วแย่ลง ────────────────────────────────
#
# **อย่ากลับไปใช้วิธีขยับสเกลอีก** วิธีที่ใช้จริงอยู่ที่ _fp16_except_rmsnorm
#
# ปัญหาจริงคือ coremltools ลด `.to(torch.float32)` ที่ transformers ใส่ไว้ใน
# Qwen2RMSNorm กันค่าล้น ให้กลับเป็น fp16 เห็นได้จาก MIL ของไฟล์ที่แปลงออกมา:
#     tensor<fp16, [1, ?, 1]> variance_1_cast_fp16 = reduce_mean(x = var_185...)
#
# เคยลองแก้ด้วยการหาร hidden ด้วย 64 ก่อนยกกำลังสอง (ผลลัพธ์เท่าเดิมในทาง
# คณิตศาสตร์) แต่กลายเป็นย้ายจากค่าล้นไปเป็นค่าจม — x^2 เล็กลง 4096 เท่า ส่วน
# fp16 เก็บค่าต่ำสุดได้ราว 6e-8 เวกเตอร์ที่ RMS ต่ำกว่า ~0.016 จึงได้ variance
# เป็นศูนย์ แล้ว rsqrt(0) = inf พังแบบเดียวกับที่พยายามจะกัน
#
# วัดผลได้ชัด: เคส 1 token ที่เคยตรงกับ PyTorch พังทันทีที่เปิดแพตช์นั้น ซึ่ง
# แพตช์ attention ทำให้เกิดไม่ได้ (ที่ ctx=1 softmax ของค่าเดียวได้ 1.0 เส้นทาง
# Q/K ไม่มีผล) ฝั่ง PyTorch มองไม่เห็นเพราะคำนวณ RMSNorm เป็น fp32 อยู่แล้ว
#
# ── กัน attention score ล้นใน fp16 ─────────────────────────────────────────
#
# transformers คำนวณ `matmul(q, k^T) / sqrt(head_dim)` โดยหาร **หลัง** matmul
# ตัว matmul จึงต้องเก็บผลรวมดิบ 128 มิติไว้ก่อน วัดจากโมเดลจริงแล้ว |k| สูงถึง
# 317 และ |q| ราว 35 ผลรวมจึงขึ้นถึงหลักล้าน ทะลุเพดาน fp16 (65504) กลายเป็น inf
#
# อาการที่ตรงกันทุกข้อ:
#   ctx = 1  -> ถูกเสมอ เพราะ softmax ของค่าเดียวได้ 1.0 ไม่ว่าค่านั้นจะเป็น inf
#   ctx >= 2 -> softmax(inf, inf) ให้ NaN หรือขยะ
#   ผลต่างกันตาม computeUnits เพราะแต่ละ backend จัดการ inf คนละแบบ
#
# วิธีแก้ — ย้ายการหารไปไว้ *ก่อน* matmul ผลลัพธ์เท่าเดิมทุกประการเพราะ
# (q/A)·k / (sqrt(d)/A) = q·k / sqrt(d) แต่ค่าที่สะสมระหว่างทางเล็กลง A เท่า
#
# ทำโดยไม่แตะ forward ของ transformers เลย — ย่อน้ำหนัก q_proj ลง A แล้วสวม
# shim ให้ `math.sqrt` ในโมดูลนั้นคืนค่าที่เล็กลง A เท่าตาม การเขียน forward
# ใหม่ทั้งก้อนจะผูกกับรายละเอียดภายในของ transformers รุ่นนั้น ๆ ซึ่งเปราะกว่ามาก
#
# ค่า ATTN_SCALE ประกาศไว้ข้างบนแล้ว เพราะชื่อ checkpoint ต้องอ้างถึงมัน


class _ScaledMath:
    """ส่งต่อทุกอย่างให้ math ยกเว้น sqrt ที่คืนค่าเล็กลง ATTN_SCALE เท่า"""

    def __getattr__(self, name):
        return getattr(math, name)

    def sqrt(self, x):
        return math.sqrt(x) / ATTN_SCALE


def _scale_down_queries(model):
    for layer in model.model.layers:
        q_proj = layer.self_attn.q_proj
        q_proj.weight.data /= ATTN_SCALE
        if q_proj.bias is not None:
            q_proj.bias.data /= ATTN_SCALE


# ── เลิกตัดตาราง RoPE ตามความยาว ───────────────────────────────────────────
#
# `Qwen2RotaryEmbedding.forward` คืน `cos_cached[:seq_len]` โดย seq_len มาจาก
# รูปร่างของ input — ซึ่งเป็นจุดที่ Core ML ทำพัง
#
# อาการ: เรียก q=1 ติดกัน สองครั้งแรกถูก ครั้งที่สามเป็นต้นไปผิด และผิดแบบ
# deterministic เหมือนกันทุก backend พิสูจน์ว่าเป็นเรื่อง specialization ที่
# cache ไว้ตามรูปร่าง input ได้จากการแทรกการเรียกที่ "รูปร่างต่างกัน" คั่น
# แล้วหายสนิท ส่วนการแทรกที่ "รูปร่างเดียวกัน" ไม่ช่วยเลย
#
#   ไม่คั่น              k1=0.000  k2=0.001  k3=0.531  k4=1.014
#   คั่นรูปร่างเดียวกัน   k1=0.000  k2=0.001  k3=0.531  k4=1.014
#   คั่นรูปร่างอื่น       k1=0.000  k2=0.001  k3=0.001  k4=0.001
#
# ที่ตรงกับหลักฐานคือ ช่อง cache ถูกเขียนครบทุกช่อง (ดัชนีเขียนถูก) แต่ค่า K
# ของช่องล่าสุดผิดตั้งแต่ layer 0 ซึ่ง K = k_proj(hidden) + RoPE — input เหมือนกัน
# ทั้งสองทาง เหลืออย่างเดียวคือตำแหน่ง RoPE ผิด
#
# ถ้าความยาวที่ใช้ตัดตารางค้างอยู่ที่ค่าเก่า การ gather ตำแหน่งล่าสุดจะหลุดขอบ
# ตาราง แล้วได้ค่าของตำแหน่งอื่นมาแทน
#
# แก้โดยคืนทั้งตาราง ไม่ตัดเลย — `apply_rotary_pos_emb` เลือกแถวด้วย
# position_ids อยู่แล้ว การตัดก่อนจึงไม่จำเป็นตั้งแต่แรก และตารางทั้งก้อนก็แค่
# 32768 x 128 ซึ่งอยู่ในไฟล์อยู่แล้ว ไม่ได้โตขึ้น
def _full_table_rope_forward(self, x, seq_len=None):
    return (
        self.cos_cached.to(dtype=x.dtype),
        self.sin_cached.to(dtype=x.dtype),
    )


# ── กัน RMSNorm ล้น โดยไม่ให้ coremltools ลดมันเป็น fp16 ───────────────────
#
# นี่คือวิธีที่ถูกของปัญหาที่เคยพยายามแก้ด้วยการขยับสเกลแล้วพัง (ดูคอมเมนต์
# ข้างบน) — แทนที่จะไปยุ่งกับตัวเลข ก็บอกตัวแปลงตรง ๆ ว่าอย่าลด op พวกนี้
#
# ข้อเท็จจริงที่ชี้มาที่นี่: หลังแก้ ATTN_SCALE แล้ว **PyTorch fp16 ตอบถูก
# แต่ Core ML fp16 จากโมเดลตัวเดียวกันยังพ่นขยะ และผลยังเปลี่ยนตาม
# computeUnits** ความต่างที่รู้จักระหว่างสองทางนี้มีอย่างเดียวคือ transformers
# คำนวณ variance ของ RMSNorm ด้วย fp32 (`.to(torch.float32)`) ส่วน
# compute_precision=FLOAT16 ลดมันกลับเป็น fp16
#
# op สามตัวนี้ปรากฏเฉพาะใน RMSNorm ของโมเดลนี้เท่านั้น การกันไว้จึงตรงจุด
# ไม่กระทบส่วนอื่น:
#   pow          ยกกำลังสองของ hidden state
#   reduce_mean  เฉลี่ยข้าม 1536 มิติ — จุดที่ล้น
#   rsqrt        ส่วนกลับของรากที่สอง
#
# coremltools จะแทรก cast fp16 -> fp32 ให้เองรอบ ๆ op ที่ถูกกันไว้
RMSNORM_OPS = ("pow", "reduce_mean", "rsqrt")


def _fp16_except_rmsnorm(op):
    """คืน True ถ้าให้แปลง op นั้นเป็น fp16 — คืน False คือคงไว้ที่ fp32"""
    return op.op_type not in RMSNORM_OPS


def _assert_state_writes(package_path, min_writes=1):
    """ตรวจว่ากราฟ *เขียน* KV cache จริง ไม่ใช่แค่อ่าน

    ด่านนี้มีเพราะเคยเสียรอบแปลงเต็ม ๆ ไปฟรีมาแล้ว: การเขียนลง view ของ state
    (`self.k[layer_idx].scatter_(...)`) ถูก coremltools ตัดทิ้งเป็น dead code
    แปลงผ่านหมด ไม่มี error สักบรรทัด ได้ไฟล์ครบ แต่ cache เป็นศูนย์ตลอด
    กว่าจะรู้ก็ตอนรันบนแมคแล้วเจอคำตอบเป็นขยะที่เหมือนกันทุก prompt

    เช็กจากไบต์ของ .mlmodel ตรง ๆ ไม่ต้องโหลดโมเดล (Colab เป็น Linux โหลดไม่ได้)
    ชื่อ op ฝังเป็นสตริงอยู่ใน protobuf อยู่แล้ว

    จำนวนที่ควรได้คือ 2 x จำนวนชั้น (k กับ v ชั้นละครั้ง) — Qwen2.5-1.5B = 56
    """
    model_file = os.path.join(package_path, "Data", "com.apple.CoreML", "model.mlmodel")
    with open(model_file, "rb") as handle:
        blob = handle.read()
    writes = blob.count(b"coreml_update_state")
    reads = blob.count(b"read_state")
    print(f"state: เขียน {writes} ครั้ง / อ่าน {reads} ครั้ง")
    if writes < min_writes:
        raise RuntimeError(
            f"กราฟไม่ได้เขียน KV cache เลย (coreml_update_state = {writes}) — "
            "โมเดลนี้ใช้ไม่ได้ ห้ามอัปโหลด ดูคอมเมนต์ใน FixedShapeKeyValueCache.update"
        )


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
        self.cache_shape = (
            cfg.num_hidden_layers,
            1,
            cfg.num_key_value_heads,
            max_context,
            head_dim,
        )

        # buffer เป็นเจ้าของ tensor แต่ผู้เดียว ชื่อสองอันนี้ต้องตรงกับ
        # ct.StateType(name=...) ตอน convert และตรงกับที่ฝั่ง Swift เรียกใช้
        #
        # fp32 ทั้งที่โมเดลเป็น fp16 — ตั้งใจ ไม่ใช่พลาด กราฟที่ frontend ของ
        # coremltools สร้างมองก้อนนี้เป็น fp32 (เห็นจาก error ของ scatter_along_axis
        # ที่บอกว่า `data` เป็น fp32) การประกาศฝั่ง torch ให้ตรงกับที่กราฟเห็นจริง
        # ทำให้แคสต์อยู่ที่เดียวคือตอนเขียนใน `update()` ไม่กระจายไปทั่ว
        #
        # ค่าที่ประกาศตรงนี้ไม่เกี่ยวกับ dtype ของ state ที่ออกไปถึงแอป — ตัวนั้นคุมด้วย
        # ct.StateType(wrapped_type=...) ซึ่งยังเป็น fp16 ตามที่ Core ML บังคับ
        self.register_buffer(
            "keyCache", torch.zeros(self.cache_shape, dtype=torch.float32)
        )
        self.register_buffer(
            "valueCache", torch.zeros(self.cache_shape, dtype=torch.float32)
        )

        # object.__setattr__ ข้าม nn.Module.__setattr__ ไปเลย ทำให้ kv_cache
        # ไม่ถูกจดใน _modules — ไม่งั้น (เพราะ Cache สืบทอด nn.Module ตั้งแต่
        # transformers 4.41) tensor ก้อนเดียวจะเข้าถึงได้ทั้งทาง keyCache และ
        # ทาง kv_cache.k ซึ่งทำให้ coremltools เทียบ IR กับ state_dict ไม่ตรง
        object.__setattr__(
            self,
            "kv_cache",
            FixedShapeKeyValueCache(
                k=self.keyCache, v=self.valueCache, max_context=max_context
            ),
        )

    def forward(self, input_ids, causal_mask, position_ids):
        # ตำแหน่งมาจาก input ตรง ๆ ไม่คำนวณจากรูปร่างอีกแล้ว — เป็นทั้งตำแหน่งของ
        # RoPE และดัชนีที่จะเขียนลง cache ใช้ค่าเดียวกันทั้งสองงานจึงไม่มีทางเพี้ยนกัน
        # `.long()` เพราะ `scatter_` รับ index เป็น int64 เท่านั้น ส่วน input ฝั่ง
        # Core ML เป็น int32 (ชนิดที่ Core ML รับสำหรับ integer input)
        self.kv_cache.positions = position_ids[0].long()
        logits = self.model(
            input_ids=input_ids,
            attention_mask=causal_mask,
            position_ids=position_ids,
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
    # โหลดเป็น fp16 เพราะ **Core ML รับ state เป็น fp16 เท่านั้น**
    # (`ValueError: State only support fp16 dtype`) — ข้อบังคับนี้อยู่ที่
    # ct.StateType ตอน convert ซึ่งยังเป็น fp16 อยู่ ส่วน buffer ฝั่ง torch
    # ประกาศเป็น fp32 ให้ตรงกับที่กราฟของ frontend มองเห็น (ดู register_buffer)
    #
    # เคยลองเปลี่ยนเป็น fp32 ด้วยเหตุผลว่า PyTorch รัน fp16 บน CPU แล้วได้ NaN
    # (จริง — ดู verify_wrapper.py) แต่แนวทางนั้นตกไปสองชั้น: ct.convert ปฏิเสธ
    # ตั้งแต่ต้นเพราะ state ไม่ใช่ fp16 และที่สำคัญกว่าคือ **ไม่มี NaN ในไฟล์ที่
    # แปลงออกมาจริง** — สแกน fp16 blob ครบทั้ง 343 ก้อนแล้วไม่เจอสักตัว และ
    # ไม่มีคำว่า nan ใน MIL เลย constant folding จึงไม่เคยผลิต NaN ออกมา
    print("Loading model...")
    torch_model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True,
        attn_implementation="eager",
    )
    torch_model.eval()

    # ต้องแพตช์ก่อน trace — กราฟจะได้จับรูปที่กันการล้นไว้แล้ว
    qwen2_mod.math = _ScaledMath()
    qwen2_mod.Qwen2RotaryEmbedding.forward = _full_table_rope_forward
    _scale_down_queries(torch_model)
    print(
        f"แพตช์แล้ว — attention หารด้วย {ATTN_SCALE:.0f} ก่อน matmul, "
        "RoPE ใช้ทั้งตารางไม่ตัดตามความยาว"
    )

    # ── พิสูจน์ว่าแพตช์ได้ผล ก่อนจะเสียเวลาแปลงสี่สิบนาที ──────────────────
    #
    # โมเดลนี้รัน fp16 บน CPU แล้วเคยได้ NaN ล้วน (ดู verify_wrapper.py) ซึ่งเป็น
    # อาการของค่าล้นแบบเดียวกัน ถ้าต้นเหตุคือ RMSNorm จริง การแพตช์ต้องทำให้
    # fp16 กลับมาทำงานได้ด้วย — และต้องตอบ ' Paris' (id 12095) ให้ถูก
    #
    # ถ้าตรงนี้ยังพัง อย่าแปลงต่อ ไปหาจุดล้นจุดอื่นก่อน
    with torch.no_grad():
        _check = torch_model(
            input_ids=torch.tensor([[785, 6722, 315, 9625, 374]])  # "The capital of France is"
        ).logits[0, -1]
    if torch.isnan(_check).any() or torch.isinf(_check).any():
        raise SystemExit(
            "fp16 forward ยังได้ NaN/Inf หลังแพตช์ — ยังมีจุดล้นที่อื่นอีก\n"
            "ลองเพิ่ม ATTN_SCALE เป็น 256 ดูก่อน"
        )
    _top = int(_check.argmax())
    print(f"fp16 forward ผ่าน — token อันดับหนึ่งคือ id {_top} (ต้องเป็น 12095 = ' Paris')")
    if _top != 12095:
        raise SystemExit("ตอบผิดตั้งแต่ใน PyTorch fp16 — อย่าแปลงต่อ")
    del _check

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
    # mask ตัวอย่างต้องเป็น dtype เดียวกับน้ำหนัก ไม่งั้น attention จะ upcast
    # ให้เองแล้วกราฟจะมี cast แปลกปลอมโผล่มา
    torch_dtype = next(torch_model.parameters()).dtype
    # trace ด้วยรูปของ prefill (q = PREFILL_CHUNK) เพราะเป็นรูปที่ใหญ่กว่า
    # mask กว้างเต็ม MAX_CONTEXT เสมอ ไม่ว่าจะ prefill หรือ decode
    example_ids = torch.zeros((1, PREFILL_CHUNK), dtype=torch.int32)
    example_mask = torch.zeros((1, 1, PREFILL_CHUNK, MAX_CONTEXT), dtype=torch_dtype)
    example_positions = torch.arange(PREFILL_CHUNK, dtype=torch.int32).unsqueeze(0)

    # TracerWarning เรื่อง "Converting a tensor to a Python boolean/integer"
    # จะโผล่มาหลายบรรทัดตรงนี้ — ปกติสำหรับดีไซน์นี้ ทุกอันเป็นเรื่องของ shape
    # ไม่ใช่ค่าใน tensor จึงไม่กระทบความถูกต้องของกราฟ
    print("Tracing...")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (example_ids, example_mask, example_positions))

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
    # ── ไม่มีมิติที่เปลี่ยนได้เลย ───────────────────────────────────────────
    #
    # `RangeDim` เปิดช่องให้ Core ML ต้องคิดขนาดเองตอนรัน ซึ่งเป็นจุดที่พังมาแล้ว
    # สองแบบ (ดูคอมเมนต์ยาวที่ FixedShapeKeyValueCache) `EnumeratedShapes` บอกไป
    # ตรง ๆ ว่ามีแค่สองรูป Core ML จึงคอมไพล์แผนตายตัวไว้สองชุด ไม่ต้องเดาอะไรเลย
    #
    #   decode  : q = 1
    #   prefill : q = PREFILL_CHUNK  (ก้อนสุดท้ายที่สั้นกว่านี้ให้ฝั่ง Swift เติมให้เต็ม
    #             แล้วปิดส่วนที่เติมด้วย mask)
    #
    # mask กว้าง MAX_CONTEXT เสมอทั้งสองรูป
    ids_shapes = ct.EnumeratedShapes(shapes=[[1, 1], [1, PREFILL_CHUNK]])
    mask_shapes = ct.EnumeratedShapes(
        shapes=[[1, 1, 1, MAX_CONTEXT], [1, 1, PREFILL_CHUNK, MAX_CONTEXT]]
    )
    position_shapes = ct.EnumeratedShapes(shapes=[[1, 1], [1, PREFILL_CHUNK]])

    print("Converting to Core ML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=ids_shapes, dtype=np.int32),
            ct.TensorType(name="causal_mask", shape=mask_shapes, dtype=np.float16),
            ct.TensorType(name="position_ids", shape=position_shapes, dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="logits", dtype=np.float16)],
        # Core ML รองรับ state เป็น fp16 อย่างเดียว ห้ามเปลี่ยน
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
        compute_precision=ct.transform.FP16ComputePrecision(
            op_selector=_fp16_except_rmsnorm
        ),
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

# ตรวจ **นอก** if/else โดยตั้งใจ — ทางที่ resume จาก checkpoint ก็ต้องโดนตรวจด้วย
# ไม่งั้น checkpoint พัง ๆ ที่ค้างอยู่จะไหลผ่านไป quantize ได้เหมือนเดิม
_assert_state_writes(FP16_PATH)


# ── quantize ──────────────────────────────────────────────────────────────
#
# per_block granularity (block 32) เสียคุณภาพน้อยกว่า per_channel ชัดเจนที่
# ระดับ 4 บิต โดยขนาดโตขึ้นแค่ไม่กี่เปอร์เซ็นต์จาก scale ที่ต้องเก็บเพิ่ม
#
# op_type_configs ตั้งได้ต่อเมื่อ untie แล้วเท่านั้น — ตอนที่ยัง tie อยู่
# const ก้อนเดียวป้อนทั้ง gather และ linear การให้คนละ config จะได้
# ValueError: compression config conflict detected
#
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
def _const_outputs(model):
    """คืน (ชื่อ, รูปร่าง) ของ const ทุกก้อนในกราฟ

    เดินบน protobuf ของ spec เองแทนที่จะใช้ `get_weights_metadata` เพราะตัวนั้น
    พังใน coremltools 8.3 — มันวน `child_op.inputs.items()` แล้วสะดุด op ที่รับ
    input เป็น list (เช่น `concat`) ได้ AttributeError: 'list' object has no
    attribute 'val' ซึ่งไม่เกี่ยวกับโมเดลเราเลย

    ใน MIL ชื่อของ const คือชื่อ output ของมัน
    """
    found = []
    for function in model.get_spec().mlProgram.functions.values():
        for block in function.block_specializations.values():
            for op in block.operations:
                if op.type != "const":
                    continue
                for out in op.outputs:
                    dims = out.type.tensorType.dimensions
                    shape = []
                    for d in dims:
                        shape.append(d.constant.size if d.HasField("constant") else -1)
                    found.append((out.name, tuple(shape)))
    return found


def find_rope_consts(model, table_shape):
    """หาตาราง cos/sin ของ RoPE

    หาโดย **รูปร่าง** ไม่ใช่ชื่อ เพราะชื่อเปลี่ยนไปตามว่าโค้ดฝั่ง PyTorch แตะ
    ตารางยังไง — ตอนที่ยังตัดตารางด้วย seq_len ชื่อจะเป็น
    `model_model_layers_0_self_attn_rotary_emb_cos_cached` แต่พอเลิกตัด
    coremltools พับ `.to(dtype)` เป็น const ก้อนใหม่ที่ไม่มีชื่อนั้นติดมาแล้ว
    ส่วนรูปร่าง [max_position_embeddings, head_dim] ไม่เปลี่ยนตามอะไรทั้งนั้น
    """
    return [name for name, shape in _const_outputs(model) if shape == table_shape]


if QUANT_DTYPE is None:
    print("ข้าม quantize ทั้งขั้น — เซฟเป็น fp16 ตามที่ตั้ง QUANT_DTYPE = None")
else:
    rope_shape = (ROPE_TABLE_ROWS, HEAD_DIM)
    rope_consts = find_rope_consts(mlmodel, rope_shape)
    if len(rope_consts) != 2:
        shapes = sorted({sh for _, sh in _const_outputs(mlmodel) if len(sh) == 2}, reverse=True)
        raise SystemExit(
            f"หาตาราง RoPE รูป {rope_shape} เจอ {len(rope_consts)} ก้อน ต้องเจอ 2 (cos กับ sin)\n"
            "อย่าปล่อยผ่าน ถ้า quantize ทับตารางนี้โมเดลจะพ่นขยะโดยไม่มี error\n"
            f"รูปร่าง 2 มิติที่มีในกราฟ: {shapes[:12]}"
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

# ── ยืนยันว่า quantize ทำงานจริง ก่อนจะเซฟ ─────────────────────────────────
#
# เคยพลาดมาแล้ว: ขั้น quantize หลุดไปอยู่ในบล็อกที่ไม่ถูกเรียก สคริปต์จึงเซฟไฟล์
# fp16 3.1 GB ออกมาโดยใช้ชื่อ Qwen-int4 และไม่มี error อะไรเลย จับได้ตอนดูขนาด
# ไฟล์เท่านั้น
if QUANT_DTYPE is not None:
    _quantized = any(
        op.type == "constexpr_blockwise_shift_scale"
        for function in mlmodel.get_spec().mlProgram.functions.values()
        for block in function.block_specializations.values()
        for op in block.operations
    )
    if not _quantized:
        raise SystemExit(
            f"ตั้ง QUANT_DTYPE = {QUANT_DTYPE!r} ไว้ แต่ในกราฟไม่มี const ที่ถูก quantize เลย\n"
            "แปลว่าขั้น quantize ไม่ได้ทำงาน อย่าเซฟไฟล์นี้"
        )

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
