"""Export + int8-dynamic-quantize the embedding model at image build time."""

import os
import shutil

from optimum.onnxruntime import ORTModelForFeatureExtraction, ORTQuantizer
from optimum.onnxruntime.configuration import AutoQuantizationConfig
from transformers import AutoTokenizer

from model_contract import MODEL_ID, ONNX_DIR

_onnx_dir = os.environ.get("ONNX_BUILD_DIR", ONNX_DIR)


def main():
    staged = "/tmp/staged"
    shutil.rmtree(staged, ignore_errors=True)
    shutil.rmtree(_onnx_dir, ignore_errors=True)
    os.makedirs(_onnx_dir, exist_ok=True)

    model = ORTModelForFeatureExtraction.from_pretrained(
        MODEL_ID,
        export=True,
        provider="CPUExecutionProvider",
    )
    model.save_pretrained(staged)
    AutoTokenizer.from_pretrained(MODEL_ID).save_pretrained(staged)

    quantizer = ORTQuantizer.from_pretrained(staged, file_name="model.onnx")
    quantization_config = AutoQuantizationConfig.avx512(is_static=False)
    quantizer.quantize(
        save_dir=_onnx_dir,
        quantization_config=quantization_config,
        use_external_data_format=False,
    )

    for name in ("tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "vocab.txt"):
        src = os.path.join(staged, name)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(_onnx_dir, name))

    shutil.rmtree(staged, ignore_errors=True)
    print(f"Model exported and int8-quantized into {_onnx_dir}: {sorted(os.listdir(_onnx_dir))}")


if __name__ == "__main__":
    main()