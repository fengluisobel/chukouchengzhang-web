#!/usr/bin/env python3
import argparse
import json
import math
import os
import sys


def check_install():
    try:
        import faster_whisper  # noqa: F401
        return {
            "ok": True,
            "installed": True,
            "provider": "faster-whisper"
        }
    except Exception as exc:
        return {
            "ok": False,
            "installed": False,
            "provider": "faster-whisper",
            "error": f"{type(exc).__name__}: {exc}"
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--audio")
    parser.add_argument("--model", default=os.environ.get("CKCZ_STT_MODEL", "small"))
    parser.add_argument("--model-path", default=os.environ.get("CKCZ_STT_MODEL_PATH", ""))
    parser.add_argument("--device", default=os.environ.get("CKCZ_STT_DEVICE", "cpu"))
    parser.add_argument("--compute-type", default=os.environ.get("CKCZ_STT_COMPUTE_TYPE", "int8"))
    parser.add_argument("--language", default="zh")
    parser.add_argument("--initial-prompt", default="")
    args = parser.parse_args()

    if args.check:
        print(json.dumps(check_install(), ensure_ascii=False))
        return 0

    if not args.audio:
        print(json.dumps({"ok": False, "error": "AUDIO_REQUIRED"}, ensure_ascii=False))
        return 2

    status = check_install()
    if not status.get("ok"):
        print(json.dumps(status, ensure_ascii=False))
        return 3

    try:
        from faster_whisper import WhisperModel

        model_ref = args.model_path or args.model
        model = WhisperModel(model_ref, device=args.device, compute_type=args.compute_type)
        segments, info = model.transcribe(
            args.audio,
            language=args.language or None,
            vad_filter=True,
            initial_prompt=args.initial_prompt or None,
            beam_size=5,
        )

        items = []
        texts = []
        for segment in segments:
            text = (segment.text or "").strip()
            if not text:
                continue
            texts.append(text)
            items.append({
                "start": round(float(segment.start), 3),
                "end": round(float(segment.end), 3),
                "text": text,
            })

        merged = " ".join(texts).strip()
        duration = None
        if getattr(info, "duration", None) is not None:
            duration = round(float(info.duration), 3)
        elif items:
            duration = round(float(items[-1]["end"]), 3)

        payload = {
            "ok": True,
            "provider": "faster-whisper",
            "model": args.model,
            "modelPath": args.model_path or None,
            "device": args.device,
            "computeType": args.compute_type,
            "language": getattr(info, "language", None) or args.language or "zh-CN",
            "duration": duration,
            "wordCount": len(merged),
            "text": merged,
            "segments": items,
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({
            "ok": False,
            "provider": "faster-whisper",
            "error": f"{type(exc).__name__}: {exc}"
        }, ensure_ascii=False))
        return 4


if __name__ == "__main__":
    sys.exit(main())
