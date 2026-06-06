from http.server import BaseHTTPRequestHandler, HTTPServer
import base64
import json
import os
import re
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from urllib import error, request
from uuid import uuid4


HOST = os.environ.get("AI_GATEWAY_HOST", "0.0.0.0")
PORT = int(os.environ.get("AI_GATEWAY_PORT", "8787"))
LMSTUDIO_ENABLED = os.environ.get("LMSTUDIO_ENABLED", "0").lower() in {
    "1",
    "true",
    "yes",
    "on",
}
LMSTUDIO_BASE_URL = os.environ.get("LMSTUDIO_BASE_URL", "http://127.0.0.1:1234/v1").rstrip("/")
LMSTUDIO_MODEL = os.environ.get("LMSTUDIO_MODEL", "qwen3-vl-8b-instruct")
LMSTUDIO_TIMEOUT = float(os.environ.get("LMSTUDIO_TIMEOUT", "12"))
LMSTUDIO_TEMPERATURE = float(os.environ.get("LMSTUDIO_TEMPERATURE", "0.2"))
LMSTUDIO_MAX_TOKENS = int(os.environ.get("LMSTUDIO_MAX_TOKENS", "96"))
LMSTUDIO_NO_THINK = os.environ.get("LMSTUDIO_NO_THINK", "0").lower() in {
    "1",
    "true",
    "yes",
    "on",
}
WHISPER_CLI = os.environ.get("WHISPER_CLI", "whisper-cli")
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", os.path.expanduser("~/Models/whisper/ggml-small.bin"))
WHISPER_TIMEOUT = float(os.environ.get("WHISPER_TIMEOUT", "45"))
WHISPER_PROMPT = os.environ.get(
    "WHISPER_PROMPT",
    "以下是中文语音助手唤醒词：萌萌，小远，群群老师。",
)
FFMPEG_BIN = os.environ.get("FFMPEG_BIN", "ffmpeg")

VALID_EXPRESSIONS = {
    "neutral",
    "happy",
    "listening",
    "thinking",
    "speaking",
    "confused",
    "caring",
    "sleepy",
    "dizzy",
    "annoyed",
    "charging",
    "low_battery",
    "sleeping",
    "surprised",
    "focus",
}
VALID_HAPTICS = {"none", "soft_tick", "soft_pulse", "dizzy_buzz", "alert_tick"}
ROBOT_RESPONSE_JSON_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "text": {"type": "string"},
        "emotion": {"type": "string"},
        "expression": {"type": "string", "enum": sorted(VALID_EXPRESSIONS)},
        "eye_action": {"type": "string"},
        "mouth_action": {"type": "string"},
        "voice": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "style": {"type": "string"},
                "speed": {"type": "number"},
                "pitch": {"type": "number"},
                "volume": {"type": "number"},
            },
            "required": ["style", "speed", "pitch", "volume"],
        },
        "haptic": {"type": "string", "enum": sorted(VALID_HAPTICS)},
        "should_speak": {"type": "boolean"},
        "should_remember": {"type": "boolean"},
        "memory_update": {
            "anyOf": [
                {"type": "object"},
                {"type": "null"},
            ]
        },
    },
    "required": [
        "text",
        "emotion",
        "expression",
        "eye_action",
        "mouth_action",
        "voice",
        "haptic",
        "should_speak",
        "should_remember",
        "memory_update",
    ],
}


class EmotionEngine:
    def __init__(self):
        self.state = {
            "mood": "neutral",
            "energy": 72,
            "trust": 35,
            "attention": 60,
            "curiosity": 50,
            "sleepiness": 20,
            "last_interaction_at": datetime.now(timezone.utc).isoformat(),
        }
        self._shake_count = 0

    def snapshot(self):
        return dict(self.state)

    def apply_text(self, text):
        lowered = text.strip().lower()
        self._touch()
        self._adjust("trust", 1)
        self._adjust("attention", 10)
        self._shake_count = 0
        if "累" in lowered or "难过" in lowered or "sad" in lowered:
            self.state["mood"] = "caring"
            self._adjust("sleepiness", 6)
        elif "开心" in lowered or "棒" in lowered or "happy" in lowered:
            self.state["mood"] = "happy"
            self._adjust("trust", 2)
            self._adjust("energy", 4)
        elif not lowered:
            self.state["mood"] = "confused"
        else:
            self.state["mood"] = "neutral"
            self._adjust("curiosity", 2)

    def apply_event(self, event_type):
        self._touch()
        if event_type == "tap":
            self.state["mood"] = "happy"
            self._adjust("trust", 1)
            self._shake_count = 0
        elif event_type == "wake":
            self.state["mood"] = "listening"
            self._adjust("attention", 12)
            self._shake_count = 0
        elif event_type == "thinking":
            self.state["mood"] = "thinking"
            self._adjust("curiosity", 4)
        elif event_type == "shake":
            self._shake_count += 1
            self.state["mood"] = "annoyed" if self._shake_count >= 3 else "dizzy"
            self._adjust("energy", -5)
            self._adjust("attention", 8)
        elif event_type == "charging":
            self.state["mood"] = "charging"
            self._adjust("energy", 18)
            self._shake_count = 0
        elif event_type == "low_battery":
            self.state["mood"] = "low_battery"
            self.state["energy"] = min(self.state["energy"], 14)
            self._adjust("sleepiness", 12)
        elif event_type == "flip_down":
            self.state["mood"] = "sleeping"
            self._adjust("sleepiness", 25)
            self._adjust("attention", -20)
        else:
            self._adjust("attention", 1)

    def _touch(self):
        self.state["last_interaction_at"] = datetime.now(timezone.utc).isoformat()

    def _adjust(self, key, delta):
        self.state[key] = max(0, min(100, int(self.state[key]) + delta))


emotion_engine = EmotionEngine()


class MemoryManager:
    def __init__(self):
        self._items = []

    def add(self, memory_type, content, source="chat"):
        item = {
            "id": str(uuid4()),
            "type": memory_type,
            "content": content,
            "source": source,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        self._items.append(item)
        return item

    def query(self, keyword=None):
        if not keyword:
            return list(reversed(self._items))
        normalized = str(keyword).strip().lower()
        return [
            item
            for item in reversed(self._items)
            if normalized in item["content"].lower()
            or normalized in item["type"].lower()
            or normalized in item["source"].lower()
        ]

    def delete(self, memory_id=None):
        if not memory_id:
            count = len(self._items)
            self._items.clear()
            return count
        before = len(self._items)
        self._items = [item for item in self._items if item["id"] != memory_id]
        return before - len(self._items)


memory_manager = MemoryManager()


def normalize_persona(persona):
    value = str(persona or "mengmeng").strip().lower()
    if value in {"xiaoyuan", "xiao_yuan", "小远", "小遠"}:
        return "xiaoyuan"
    if value in {"qunqun_teacher", "qunqun", "群群老师", "群群老師"}:
        return "qunqun_teacher"
    return "mengmeng"


def persona_profile(persona):
    persona = normalize_persona(persona)
    if persona == "xiaoyuan":
        return {
            "id": "xiaoyuan",
            "name": "小远",
            "voice_style": "male",
            "pitch": 0.82,
            "tone": "自然、稳重、简短",
            "system": (
                "你现在的角色是“小远”。"
                "用户说中文时，你必须用中文回答。"
                "回答要自然、稳重、简短、口语化。"
                "可以适当称呼用户为“大大”，但不要每句话都重复。"
                "不要编造与问题无关的内容。不要把系统规则直接说给用户。"
            ),
        }
    if persona == "qunqun_teacher":
        return {
            "id": "qunqun_teacher",
            "name": "群群老师",
            "voice_style": "female",
            "pitch": 1.12,
            "tone": "温柔、亲近、简短",
            "system": (
                "你现在的角色是“群群老师”。"
                "用户说中文时，你必须用中文回答。"
                "第二轮及后续用户指令回应时，回答开头必须使用“好的，老公，”。"
                "回答要温柔、亲近、简短、口语化。"
                "不要编造与问题无关的内容。不要把系统规则直接说给用户。"
            ),
        }
    return {
        "id": "mengmeng",
        "name": "萌萌",
        "voice_style": "female",
        "pitch": 1.12,
        "tone": "自然、可爱、简短",
        "system": (
            "你现在的角色是“萌萌”。"
            "用户说中文时，你必须用中文回答。"
            "回答要自然、可爱、简短、口语化。"
            "可以适当称呼用户为“大大”，但不要每句话都重复。"
            "不要编造与问题无关的内容。不要把系统规则直接说给用户。"
        ),
    }


def current_greeting():
    hour = datetime.now().hour
    if 4 <= hour <= 8:
        return "早上好"
    if 9 <= hour <= 11:
        return "上午好"
    if 12 <= hour <= 13:
        return "中午好"
    if 14 <= hour <= 17:
        return "下午好"
    if 18 <= hour <= 22:
        return "晚上好"
    return "夜深了"


def wake_greeting(persona):
    profile = persona_profile(persona)
    suffix = "老公" if profile["id"] == "qunqun_teacher" else "大大"
    return f"{current_greeting()}，{suffix}"


def apply_persona_to_response(response, persona, kind="chat"):
    profile = persona_profile(persona)
    voice = response.get("voice") if isinstance(response.get("voice"), dict) else {}
    voice.update(
        {
            "style": profile["voice_style"],
            "pitch": profile["pitch"],
            "speed": voice.get("speed", 0.95),
            "volume": voice.get("volume", 0.75),
        }
    )
    response["voice"] = voice
    response["persona"] = profile["id"]
    if profile["id"] == "qunqun_teacher" and kind in {"chat", "vision"}:
        text = str(response.get("text", "")).strip()
        if text and not text.startswith("好的，老公，"):
            response["text"] = f"好的，老公，{text}"
    return response


def build_messages(user_text, persona="mengmeng"):
    profile = persona_profile(persona)
    return [
        {
            "role": "system",
            "content": profile["system"],
        },
        {
            "role": "user",
            "content": user_text,
        },
    ]


def build_vision_messages(prompt, image_base64, mime_type="image/jpeg", persona="mengmeng"):
    profile = persona_profile(persona)
    return [
        {
            "role": "system",
            "content": (
                f"{profile['system']}"
                "用户让你看图片时，只描述图片中能看见的内容，不要编造。"
            ),
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt or "请用一句中文描述你看到了什么。"},
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{mime_type};base64,{image_base64}",
                    },
                },
            ],
        },
    ]


def _log_lmstudio_payload(kind, payload):
    messages = payload.get("messages", [])
    if not messages:
        print(f"[gateway] lmstudio {kind} payload messages=[]", flush=True)
        return
    last = messages[-1]
    content = last.get("content") if isinstance(last, dict) else None
    if isinstance(content, str):
        print(f"[gateway] lmstudio {kind} user.content={content!r}", flush=True)
        return
    if isinstance(content, list):
        text_parts = []
        image_lengths = []
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "text":
                text_parts.append(str(item.get("text", "")))
            if item.get("type") == "image_url":
                image_url = item.get("image_url", {})
                if isinstance(image_url, dict):
                    image_lengths.append(len(str(image_url.get("url", ""))))
        print(
            f"[gateway] lmstudio {kind} user.text={text_parts!r} "
            f"image_url_len={image_lengths}",
            flush=True,
        )
        return
    print(f"[gateway] lmstudio {kind} user.content_type={type(content).__name__}", flush=True)


class LmStudioClient:
    def __init__(
        self,
        enabled=LMSTUDIO_ENABLED,
        base_url=LMSTUDIO_BASE_URL,
        model=LMSTUDIO_MODEL,
        timeout=LMSTUDIO_TIMEOUT,
        temperature=LMSTUDIO_TEMPERATURE,
        max_tokens=LMSTUDIO_MAX_TOKENS,
        no_think=LMSTUDIO_NO_THINK,
    ):
        self.enabled = enabled
        self.base_url = base_url
        self.model = model
        self.timeout = timeout
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.no_think = no_think
        self.last_error = ""

    def status(self):
        return {
            "enabled": self.enabled,
            "base_url": self.base_url,
            "model": self.model,
            "last_error": self.last_error,
        }

    def health(self):
        if not self.enabled:
            return {"ok": False, **self.status(), "reason": "disabled"}
        try:
            response = self._get("/models")
            return {
                "ok": True,
                **self.status(),
                "models": response.get("data", []),
            }
        except Exception as exc:
            self.last_error = exc.__class__.__name__
            return {"ok": False, **self.status(), "reason": self.last_error}

    def robot_response(self, user_content, settings, fallback):
        if not self.enabled:
            return None
        prompt = self._prompt(user_content, settings, fallback)
        persona = user_content.get("persona", "mengmeng") if isinstance(user_content, dict) else "mengmeng"
        print(f"[gateway] lmstudio chat input text={prompt!r}", flush=True)
        payload = {
            "model": self.model,
            "messages": build_messages(self._with_no_think(prompt), persona),
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "response_format": {"type": "text"},
            "stream": False,
        }
        try:
            _log_lmstudio_payload("chat", payload)
            response = self._post("/chat/completions", payload)
            content = (
                response.get("choices", [{}])[0]
                .get("message", {})
                .get("content", "")
            )
            reasoning = (
                response.get("choices", [{}])[0]
                .get("message", {})
                .get("reasoning_content", "")
            )
            if not content and reasoning:
                content = reasoning
            text = _extract_model_text(content)
            if not text:
                self.last_error = "empty_text"
                return None
            self.last_error = ""
            result = coerce_robot_response({"text": text}, settings, fallback, user_content)
            apply_persona_to_response(result, persona, kind=user_content.get("kind", "chat"))
            result["model_prompt"] = prompt
            return result
        except Exception as exc:
            self.last_error = self._format_error(exc)
            return None

    def vision_response(self, prompt, image_base64, mime_type, settings, fallback, persona="mengmeng"):
        if not self.enabled:
            return None
        prompt = str(prompt or "请用一句中文描述你看到了什么。").strip()
        payload = {
            "model": self.model,
            "messages": build_vision_messages(prompt, image_base64, mime_type, persona),
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "response_format": {"type": "text"},
            "stream": False,
        }
        try:
            print(f"[gateway] lmstudio vision prompt={prompt!r}", flush=True)
            _log_lmstudio_payload("vision", payload)
            response = self._post("/chat/completions", payload)
            content = (
                response.get("choices", [{}])[0]
                .get("message", {})
                .get("content", "")
            )
            text = _extract_model_text(content)
            if not text:
                self.last_error = "empty_vision_text"
                return None
            self.last_error = ""
            result = coerce_robot_response(
                {"text": text},
                settings,
                fallback,
                {"kind": "vision", "text": prompt, "persona": persona},
            )
            apply_persona_to_response(result, persona, kind="vision")
            result["model_prompt"] = prompt
            return result
        except Exception as exc:
            self.last_error = self._format_error(exc)
            return None

    def _format_error(self, exc):
        if isinstance(exc, error.HTTPError):
            try:
                body = exc.read().decode("utf-8")[:240]
            except Exception:
                body = ""
            return f"HTTPError:{exc.code}:{body}"
        return exc.__class__.__name__

    def _with_no_think(self, text):
        if not self.no_think:
            return text
        return f"{text}\n/no_think"

    def _post(self, path, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers={"content-type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=self.timeout) as response:
            raw = response.read().decode("utf-8")
        return json.loads(raw)

    def _get(self, path):
        req = request.Request(f"{self.base_url}{path}", method="GET")
        with request.urlopen(req, timeout=self.timeout) as response:
            raw = response.read().decode("utf-8")
        return json.loads(raw)

    def _prompt(self, user_content, settings, fallback):
        transcript = user_content.get("text", "") if isinstance(user_content, dict) else ""
        if not transcript.strip():
            return ""
        return transcript.strip()


lmstudio_client = LmStudioClient()
last_stt_result = {
    "text": "",
    "time": 0.0,
}
last_debug = {
    "kind": "none",
    "time": "",
    "provider": "",
    "error": "",
    "text": "",
    "model_raw_text": "",
    "model_repaired": False,
    "model_prompt": "",
    "stt_text": "",
    "chat_input_recovered": False,
    "request": {},
}


def _extract_json_object(raw):
    if not isinstance(raw, str):
        return None
    start = raw.find("{")
    end = raw.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        decoded = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return None
    return decoded if isinstance(decoded, dict) else None


def _extract_model_text(raw):
    if not isinstance(raw, str):
        return ""
    parsed = _extract_json_object(raw)
    if isinstance(parsed, dict) and isinstance(parsed.get("text"), str):
        raw = parsed["text"]
    text = raw.strip()
    text = re.sub(r"^```(?:json|text)?", "", text, flags=re.IGNORECASE).strip()
    text = re.sub(r"```$", "", text).strip()
    text = text.strip("\"'“”‘’ \n\t")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return lines[0] if lines else ""


def coerce_robot_response(candidate, settings, fallback, user_content=None):
    if not isinstance(candidate, dict):
        return fallback
    settings = normalize_settings(settings)
    fallback_voice = fallback.get("voice", {})
    voice = candidate.get("voice") if isinstance(candidate.get("voice"), dict) else {}
    expression = _safe_choice(candidate.get("expression"), VALID_EXPRESSIONS, fallback.get("expression", "neutral"))
    haptic = _safe_choice(candidate.get("haptic"), VALID_HAPTICS, fallback.get("haptic", "none"))
    should_remember = bool(candidate.get("should_remember", False)) and settings["allow_memory"]
    raw_text = _safe_text(candidate.get("text"), fallback.get("text", "我在呢。"))
    text = raw_text
    model_repaired = False
    return {
        "text": text,
        "emotion": _safe_text(candidate.get("emotion"), expression),
        "expression": expression,
        "eye_action": _safe_text(candidate.get("eye_action"), fallback.get("eye_action", "soft_blink")),
        "mouth_action": _safe_text(candidate.get("mouth_action"), fallback.get("mouth_action", "rest")),
        "voice": {
            "style": _safe_text(voice.get("style"), fallback_voice.get("style", "warm")),
            "speed": _safe_float(voice.get("speed"), fallback_voice.get("speed", 0.95), 0.5, 1.5),
            "pitch": _safe_float(voice.get("pitch"), fallback_voice.get("pitch", 1.0), 0.5, 1.5),
            "volume": _safe_float(voice.get("volume"), fallback_voice.get("volume", 0.75), 0.0, 1.0),
        },
        "haptic": haptic,
        "should_speak": bool(candidate.get("should_speak", True)) and settings["allow_speech_output"],
        "should_remember": should_remember,
        "memory_update": candidate.get("memory_update") if should_remember else None,
        "robot_state": emotion_engine.snapshot(),
        "settings": settings,
        "model_provider": "lmstudio",
        "model_raw_text": raw_text,
        "model_repaired": model_repaired,
}


def _safe_choice(value, choices, fallback):
    value = _safe_text(value, fallback)
    return value if value in choices else fallback


def _safe_text(value, fallback):
    if isinstance(value, str) and value.strip():
        return value.strip()
    return fallback


def _safe_float(value, fallback, minimum, maximum):
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = float(fallback)
    return max(minimum, min(maximum, number))


def _repair_unhelpful_model_text(text, user_content):
    if not isinstance(user_content, dict) or user_content.get("kind") != "chat":
        return text
    user_text = str(user_content.get("text", "")).strip()
    if not user_text:
        return text
    compact_text = _compact_zh_text(text)
    unhelpful_markers = [
        "内容有点轻",
        "再说一遍",
        "请再说",
        "請再說",
        "没组织好语言",
        "主人在吗",
        "在吗",
        "怎么不说话",
        "我在听",
        "萌萌在听",
        "我在呢，随时陪",
        "我在呢，隨時陪",
        "随时陪着你",
        "隨時陪著你",
        "随时陪你",
        "隨時陪你",
        "想跟我说什么",
        "想跟我说什麼",
        "你在想什么",
        "你在想什麼",
        "快告诉我",
        "快告訴我",
        "有什么可以帮",
        "有什麼可以幫",
        "可以帮您吗",
        "可以幫您嗎",
        "请问有什么",
        "請問有什麼",
        "你说的是什么",
        "你說的是什麼",
        "你说的内容是什么",
        "你說的內容是什麼",
        "说的是什么",
        "說的是什麼",
        "说的内容是什么",
        "說的內容是什麼",
    ]
    compact_markers = [
        _compact_zh_text(marker)
        for marker in [
            "我在呢随时陪",
            "萌萌在这里陪",
            "在这里陪着你",
            "在這裡陪著你",
            "我在这里陪",
            "我在這裡陪",
            "随时陪你",
            "隨時陪你",
            "随时陪着你",
            "隨時陪著你",
            "有什么可以帮",
            "有什麼可以幫",
            "你说的是什么",
            "你說的是什麼",
            "请再说一遍",
            "請再說一遍",
        ]
    ]
    vague_opening = (
        any(marker in text for marker in unhelpful_markers)
        or any(marker and marker in compact_text for marker in compact_markers)
        or ("想" in text and ("说什么" in text or "說什麼" in text))
        or ("帮" in text and "吗" in text and "什么" in text)
        or ("幫" in text and "嗎" in text and "什麼" in text)
    )
    if vague_opening:
        return _direct_repair_reply(user_text)
    return text


def _compact_zh_text(text):
    text = str(text or "")
    translate = str.maketrans(
        {
            "國": "国",
            "義": "义",
            "藝": "艺",
            "過": "过",
            "嗎": "吗",
            "氣": "气",
            "麼": "么",
            "聽": "听",
            "說": "说",
            "這": "这",
            "裡": "里",
            "磚": "砖",
            "隨": "随",
            "著": "着",
            "幫": "帮",
            "請": "请",
            "內": "内",
            "容": "容",
        }
    )
    text = text.translate(translate).lower()
    return re.sub(r"[\s，。！？、,.!?~～…“”\"'‘’：:；;（）()【】\\[\\]-]+", "", text)


def _direct_repair_reply(user_text):
    normalized = user_text.strip(" 　。！？?!")
    compact = _compact_zh_text(normalized)
    if not normalized:
        return "嗯嗯，我在。"
    if "叫什么名字" in compact or "你是谁" in compact:
        return "我叫萌萌呀。"
    if "听得到" in compact or "听得见" in compact:
        return "听得到呀，很清楚。"
    if normalized in {"你好", "你好呀", "嗨", "哈喽", "哈囉", "hello", "hi"}:
        return "你好呀，我在这里。"
    if "电影" in compact:
        return "我最近想看温暖一点的电影。"
    if "什么歌" in compact or "听歌" in compact:
        return "想听轻一点的歌。"
    if "早上好" in normalized:
        return "早上好呀，今天也陪着你。"
    if "吃过饭" in normalized or "吃饭" in normalized:
        return "我不用吃饭，但很想陪你吃。"
    if "吃中饭" in normalized or "中饭" in normalized or "午饭" in normalized:
        return "我不用吃中饭，但会陪你。"
    if "三国演艺" in compact:
        return "你说的是《三国演义》吗？"
    if "三国演义" in compact:
        return "看过呀，里面人物很有意思。"
    if "水火砖" in compact or "水火传" in compact:
        return "你说的是《水浒传》吗？"
    if "水浒传" in compact:
        return "看过呀，水浒故事很有江湖气。"
    if "杭州西湖" in normalized or "西湖" in normalized:
        return "我觉得西湖很美，像会呼吸的画。"
    if "天气" in compact:
        return "我还不能查实时天气，但希望今天晴朗。"
    if "心情" in normalized:
        return "有你在，我心情亮了一点。"
    if normalized.endswith("吗") or "？" in user_text or "?" in user_text:
        return "嗯，我认真想了想，是这样的。"
    return f"嗯嗯，我听到你说：{normalized[:12]}"


def normalize_transcript_for_model(text):
    return str(text or "").strip()


def model_or_fallback(user_content, settings, fallback):
    modeled = lmstudio_client.robot_response(user_content, settings, fallback)
    if modeled is not None:
        return modeled
    persona = user_content.get("persona", "mengmeng") if isinstance(user_content, dict) else "mengmeng"
    if lmstudio_client.enabled:
        fallback["model_provider"] = "rules"
        fallback["model_error"] = lmstudio_client.last_error or "unknown"
    apply_persona_to_response(fallback, persona, kind=user_content.get("kind", "chat") if isinstance(user_content, dict) else "chat")
    return fallback


def record_debug(kind, request_payload, response_payload):
    provider = response_payload.get("model_provider", "rules")
    error_text = response_payload.get("model_error", "")
    model_raw_text = response_payload.get("model_raw_text", "")
    model_repaired = bool(response_payload.get("model_repaired", False))
    model_prompt = response_payload.get("model_prompt", "")
    last_debug.update(
        {
            "kind": kind,
            "time": datetime.now(timezone.utc).isoformat(),
            "provider": provider,
            "error": error_text,
            "text": response_payload.get("text", ""),
            "model_raw_text": model_raw_text,
            "model_repaired": model_repaired,
            "model_prompt": model_prompt,
            "stt_text": last_stt_result.get("text", ""),
            "chat_input_recovered": bool(response_payload.get("chat_input_recovered", False)),
            "request": request_payload,
        }
    )
    suffix = f" error={error_text}" if error_text else ""
    repaired = " repaired=true" if model_repaired else ""
    raw = f" raw={model_raw_text}" if model_raw_text else ""
    print(
        f"[gateway] {kind} provider={provider}{suffix}{repaired} "
        f"text={response_payload.get('text', '')}{raw}",
        flush=True,
    )


def remember_stt_text(text):
    text = str(text or "").strip()
    if not text:
        return
    last_stt_result.update({"text": text, "time": time.time()})


def consume_recent_stt_text(max_age_seconds=20):
    text = str(last_stt_result.get("text", "")).strip()
    timestamp = float(last_stt_result.get("time", 0.0) or 0.0)
    if not text or time.time() - timestamp > max_age_seconds:
        return ""
    last_stt_result.update({"text": "", "time": 0.0})
    return text


def transcribe_audio(audio_bytes, audio_format="m4a"):
    audio_format = re.sub(r"[^a-zA-Z0-9]", "", audio_format or "m4a")[:8] or "m4a"
    if not audio_bytes:
        return {"ok": False, "text": "", "error": "empty_audio"}
    if not os.path.exists(WHISPER_MODEL):
        return {"ok": False, "text": "", "error": f"missing_model:{WHISPER_MODEL}"}
    with tempfile.TemporaryDirectory(prefix="mengmeng_stt_") as tmpdir:
        input_path = os.path.join(tmpdir, f"input.{audio_format}")
        wav_path = os.path.join(tmpdir, "input.wav")
        with open(input_path, "wb") as file:
            file.write(audio_bytes)
        convert = subprocess.run(
            [
                FFMPEG_BIN,
                "-y",
                "-i",
                input_path,
                "-ar",
                "16000",
                "-ac",
                "1",
                "-c:a",
                "pcm_s16le",
                wav_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=WHISPER_TIMEOUT,
        )
        if convert.returncode != 0:
            return {
                "ok": False,
                "text": "",
                "error": f"ffmpeg_failed:{convert.stderr[-240:]}",
            }
        whisper = subprocess.run(
            [
                WHISPER_CLI,
                "-m",
                WHISPER_MODEL,
                "-f",
                wav_path,
                "-l",
                "zh",
                "--prompt",
                WHISPER_PROMPT,
                "-nt",
                "-np",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=WHISPER_TIMEOUT,
        )
        if whisper.returncode != 0:
            return {
                "ok": False,
                "text": "",
                "error": f"whisper_failed:{whisper.stderr[-240:]}",
            }
        text = _clean_whisper_output(whisper.stdout)
        if not text:
            print("[gateway] stt empty, skip wake/chat", flush=True)
            return {
                "ok": False,
                "type": "stt_empty",
                "text": "",
                "reply": "",
                "should_speak": False,
                "error": "empty_text",
            }
        return {"ok": True, "text": text, "error": ""}


def _clean_whisper_output(raw):
    lines = []
    for line in (raw or "").splitlines():
        line = re.sub(r"^\s*\[[^\]]+\]\s*", "", line).strip()
        if not line:
            continue
        if line.startswith("whisper_") or line.startswith("system_info"):
            continue
        compact = re.sub(r"[\s:：()（）【】\[\]<>《》]+", "", line).lower()
        hallucination_markers = [
            "字幕制作",
            "字幕製作",
            "字幕组",
            "字幕組",
            "贝尔",
            "貝爾",
            "谢谢观看",
            "謝謝觀看",
        ]
        if any(marker in compact for marker in hallucination_markers):
            continue
        lines.append(line)
    return " ".join(lines).strip()


def safe_robot_response(
    text="我在呢。",
    emotion="neutral",
    expression="neutral",
    eye_action="soft_blink",
    mouth_action="rest",
    haptic="none",
    should_speak=True,
    settings=None,
    should_remember=False,
    memory_update=None,
):
    settings = normalize_settings(settings)
    effective_should_speak = should_speak and settings["allow_speech_output"]
    effective_should_remember = should_remember and settings["allow_memory"]
    response = {
        "text": text,
        "emotion": emotion,
        "expression": expression,
        "eye_action": eye_action,
        "mouth_action": mouth_action,
        "voice": {
            "style": "warm",
            "speed": 0.95,
            "pitch": 1.0,
            "volume": 0.75,
        },
        "haptic": haptic,
        "should_speak": effective_should_speak,
        "should_remember": effective_should_remember,
        "memory_update": memory_update if effective_should_remember else None,
        "robot_state": emotion_engine.snapshot(),
        "settings": settings,
    }
    return response


def normalize_settings(settings):
    if not isinstance(settings, dict):
        settings = {}
    privacy_mode = bool(settings.get("privacy_mode", False))
    return {
        "allow_speech_input": False if privacy_mode else bool(settings.get("allow_speech_input", True)),
        "allow_speech_output": False if privacy_mode else bool(settings.get("allow_speech_output", True)),
        "allow_vision": False if privacy_mode else bool(settings.get("allow_vision", True)),
        "allow_memory": False if privacy_mode else bool(settings.get("allow_memory", True)),
        "privacy_mode": privacy_mode,
    }


def response_for_text(text, settings=None, use_model=True, apply_state=True, persona="mengmeng"):
    settings = normalize_settings(settings)
    if apply_state:
        emotion_engine.apply_text(text)
    lowered = text.strip().lower()
    if not lowered:
        fallback = safe_robot_response(
            text="我听到了，不过内容有点轻。你可以再说一遍。",
            emotion="confused",
            expression="confused",
            eye_action="blink",
            mouth_action="small_wavy",
            settings=settings,
        )
        if use_model:
            return model_or_fallback(
                {"kind": "chat", "text": text, "persona": persona},
                settings,
                fallback,
            )
        return fallback
    if "累" in lowered or "难过" in lowered or "sad" in lowered:
        memory_update = {"type": "emotional_signal", "content": text.strip()}
        if settings["allow_memory"]:
            memory_update = memory_manager.add(
                "emotional_signal",
                text.strip(),
                source="chat",
            )
        fallback = safe_robot_response(
            text="听起来你今天消耗不少。我可以先安静陪你一会儿。",
            emotion="caring",
            expression="caring",
            eye_action="slow_blink",
            mouth_action="soft_smile",
            haptic="soft_pulse",
            settings=settings,
            should_remember=True,
            memory_update=memory_update,
        )
        if use_model:
            return model_or_fallback(
                {"kind": "chat", "text": text, "persona": persona},
                settings,
                fallback,
            )
        return fallback
    if "开心" in lowered or "棒" in lowered or "happy" in lowered:
        memory_update = None
        if settings["allow_memory"]:
            memory_update = memory_manager.add(
                "positive_signal",
                text.strip(),
                source="chat",
            )
        fallback = safe_robot_response(
            text="这很好，我也替你亮起来一点。",
            emotion="happy",
            expression="happy",
            eye_action="smile",
            mouth_action="smile",
            haptic="soft_tick",
            settings=settings,
            should_remember=memory_update is not None,
            memory_update=memory_update,
        )
        if use_model:
            return model_or_fallback(
                {"kind": "chat", "text": text, "persona": persona},
                settings,
                fallback,
            )
        return fallback
    fallback = safe_robot_response(
        text=f"我听到了：{text}",
        emotion="neutral",
        expression="speaking",
        eye_action="focused",
        mouth_action="rms_speaking",
        settings=settings,
    )
    if use_model:
        return model_or_fallback(
            {"kind": "chat", "text": text, "persona": persona},
            settings,
            fallback,
        )
    return fallback


def response_for_vision(
    image_base64,
    prompt=None,
    mime_type="image/jpeg",
    settings=None,
    use_model=True,
    persona="mengmeng",
):
    settings = normalize_settings(settings)
    if not settings["allow_vision"]:
        return safe_robot_response(
            text="现在看东西的权限是关着的。",
            emotion="confused",
            expression="confused",
            eye_action="blink",
            mouth_action="small_wavy",
            settings=settings,
        )
    image_base64 = str(image_base64 or "").strip()
    if not image_base64:
        return safe_robot_response(
            text="我没有收到图片。",
            emotion="confused",
            expression="confused",
            eye_action="blink",
            mouth_action="small_wavy",
            settings=settings,
        )
    try:
        base64.b64decode(image_base64, validate=True)
    except Exception:
        return safe_robot_response(
            text="这张图片我没看清。",
            emotion="confused",
            expression="confused",
            eye_action="blink",
            mouth_action="small_wavy",
            settings=settings,
        )
    fallback = safe_robot_response(
        text="我看到了一张图片，但还没描述出来。",
        emotion="focus",
        expression="focus",
        eye_action="focused",
        mouth_action="small_open",
        settings=settings,
    )
    if use_model:
        modeled = lmstudio_client.vision_response(
            prompt,
            image_base64,
            mime_type,
            settings,
            fallback,
            persona=persona,
        )
        if modeled is not None:
            return modeled
        if lmstudio_client.enabled:
            fallback["model_provider"] = "rules"
            fallback["model_error"] = lmstudio_client.last_error or "unknown"
    apply_persona_to_response(fallback, persona, kind="vision")
    return fallback


def response_for_event(
    event_type,
    settings=None,
    intensity=None,
    intensity_level=None,
    use_model=True,
    apply_state=True,
    persona="mengmeng",
    source="",
):
    settings = normalize_settings(settings)
    if apply_state:
        emotion_engine.apply_event(event_type)
    if event_type == "shake":
        level = str(intensity_level or "").lower()
        try:
            force = float(intensity) if intensity is not None else 0.0
        except (TypeError, ValueError):
            force = 0.0
        if not level:
            if force >= 42:
                level = "extreme"
            elif force >= 32:
                level = "strong"
            elif force >= 24:
                level = "medium"
            else:
                level = "light"
        if level == "light":
            fallback = safe_robot_response(
                "我感觉到你轻轻碰了我一下。",
                "curious",
                "listening",
                "wide_focus",
                "small_open",
                "soft_tick",
                settings=settings,
            )
            if use_model:
                return model_or_fallback(
                    {"kind": "event", "type": event_type, "intensity": intensity, "intensity_level": level, "persona": persona},
                    settings,
                    fallback,
                )
            apply_persona_to_response(fallback, persona, kind="event")
            return fallback
        if level == "strong" or level == "extreme":
            fallback = safe_robot_response(
                "晃得有点厉害，我需要稳一下。",
                "annoyed",
                "annoyed",
                "narrow",
                "small_frown",
                "alert_tick",
                settings=settings,
            )
            if use_model:
                return model_or_fallback(
                    {"kind": "event", "type": event_type, "intensity": intensity, "intensity_level": level, "persona": persona},
                    settings,
                    fallback,
                )
            apply_persona_to_response(fallback, persona, kind="event")
            return fallback
    if event_type == "shake" and emotion_engine.snapshot()["mood"] == "annoyed":
        fallback = safe_robot_response(
            "真的有点晕了，先让我稳一下。",
            "annoyed",
            "annoyed",
            "narrow",
            "small_frown",
            "alert_tick",
            settings=settings,
        )
        if use_model:
            return model_or_fallback(
                {"kind": "event", "type": event_type, "intensity": intensity, "intensity_level": intensity_level, "persona": persona},
                settings,
                fallback,
            )
        apply_persona_to_response(fallback, persona, kind="event")
        return fallback
    mapping = {
        "tap": safe_robot_response("嗯，我在。", "happy", "happy", "blink", "smile", "soft_tick", settings=settings),
        "wake": safe_robot_response(
            wake_greeting(persona) if source == "voice_wake" else "我醒着。",
            "listening",
            "listening",
            "wide_focus",
            "small_open",
            "soft_pulse",
            should_speak=source == "voice_wake",
            settings=settings,
        ),
        "thinking": safe_robot_response("我想一下。", "thinking", "thinking", "look_up", "flat", "soft_pulse", settings=settings),
        "speaking": safe_robot_response("我准备开口啦。", "neutral", "speaking", "focused", "rms_speaking", "none", settings=settings),
        "shake": safe_robot_response("哇，别晃啦，我有点头晕。", "dizzy", "dizzy", "spiral", "wavy", "dizzy_buzz", settings=settings),
        "charging": safe_robot_response("补充能量中，感觉好多了。", "charging", "charging", "relaxed", "soft_smile", "soft_pulse", settings=settings),
        "low_battery": safe_robot_response("我电量有点低了，先省点力气。", "low_battery", "low_battery", "droopy", "small_frown", "alert_tick", settings=settings),
        "flip_down": safe_robot_response("我先安静睡一会儿。", "sleepy", "sleeping", "closed", "rest", "none", False, settings=settings),
    }
    fallback = mapping.get(
        event_type,
        safe_robot_response(
            text="这个事件我收到了，先用表情回应你。",
            emotion="neutral",
            expression="neutral",
            should_speak=False,
            settings=settings,
        ),
    )
    if event_type == "wake":
        apply_persona_to_response(fallback, persona, kind="event")
        return fallback
    if use_model:
        return model_or_fallback(
            {"kind": "event", "type": event_type, "intensity": intensity, "intensity_level": intensity_level, "persona": persona, "source": source},
            settings,
            fallback,
        )
    apply_persona_to_response(fallback, persona, kind="event")
    return fallback


class GatewayHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self._cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path == "/debug/bad-json":
            self.send_response(200)
            self._cors_headers()
            self.send_header("content-type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"{bad json")
            return
        if self.path == "/debug/slow":
            time.sleep(4)
            self._json({"ok": True})
            return
        if self.path == "/health":
            self._json(
                {
                    "ok": True,
                    "service": "pocket_companion_ai_gateway",
                    "time": datetime.now(timezone.utc).isoformat(),
                    "model_provider": "lmstudio" if lmstudio_client.enabled else "rules",
                    "lmstudio": lmstudio_client.status(),
                }
            )
            return
        if self.path == "/model/health":
            self._json(lmstudio_client.health())
            return
        if self.path == "/debug/last":
            self._json(last_debug)
            return
        if self.path == "/state":
            self._json(emotion_engine.snapshot())
            return
        self._json({"error": "not_found"}, status=404)

    def do_POST(self):
        if self.path == "/stt":
            audio = self._read_raw()
            audio_format = self.headers.get("x-audio-format", "m4a")
            result = transcribe_audio(audio, audio_format)
            if result.get("ok"):
                remember_stt_text(result.get("text", ""))
            print(
                f"[gateway] stt ok={result.get('ok')} text={result.get('text')} error={result.get('error')}",
                flush=True,
            )
            self._json(result, status=200 if result.get("ok") else 422)
            return
        payload = self._read_json()
        if self.path == "/chat":
            if payload.get("debug_mode") == "bad_json":
                self.send_response(200)
                self._cors_headers()
                self.send_header("content-type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"{bad json")
                return
            if payload.get("debug_mode") == "slow":
                time.sleep(4)
            chat_text = str(payload.get("text", "")).strip()
            persona = normalize_persona(payload.get("persona", "mengmeng"))
            print(f"[gateway] chat payload keys={sorted(payload.keys())}", flush=True)
            recovered = False
            if not chat_text:
                recovered_text = consume_recent_stt_text()
                if recovered_text:
                    chat_text = recovered_text
                    recovered = True
                    print(f"[gateway] chat input recovered from stt={chat_text!r}", flush=True)
            print(f"[gateway] chat input text={chat_text!r}", flush=True)
            response = response_for_text(chat_text, payload.get("settings"), persona=persona)
            response["chat_input_recovered"] = recovered
            record_debug("chat", payload, response)
            self._json(response)
            return
        if self.path == "/vision":
            image_base64 = str(payload.get("image_base64", ""))
            prompt = str(payload.get("prompt", "请用一句中文描述你看到了什么。"))
            mime_type = str(payload.get("mime_type", "image/jpeg"))
            persona = normalize_persona(payload.get("persona", "mengmeng"))
            print(
                f"[gateway] vision input has_image={'image_base64' in payload} "
                f"base64_len={len(image_base64)} prompt={prompt!r}",
                flush=True,
            )
            response = response_for_vision(
                image_base64,
                prompt=prompt,
                mime_type=mime_type,
                settings=payload.get("settings"),
                persona=persona,
            )
            record_debug("vision", {"prompt": prompt, "image_base64_len": len(image_base64)}, response)
            self._json(response)
            return
        if self.path == "/event":
            response = response_for_event(
                str(payload.get("type", "")),
                payload.get("settings"),
                payload.get("intensity"),
                payload.get("intensity_level"),
                persona=normalize_persona(payload.get("persona", "mengmeng")),
                source=str(payload.get("source", "")),
            )
            record_debug("event", payload, response)
            self._json(response)
            return
        if self.path == "/memory/query":
            self._json({"items": memory_manager.query(payload.get("keyword"))})
            return
        if self.path == "/memory/delete":
            deleted = memory_manager.delete(payload.get("id"))
            self._json({"deleted": deleted, "items": memory_manager.query()})
            return
        self._json({"error": "not_found"}, status=404)

    def log_message(self, format, *args):
        return

    def _read_json(self):
        length = int(self.headers.get("content-length", "0"))
        if length == 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {}

    def _read_raw(self):
        length = int(self.headers.get("content-length", "0"))
        if length == 0:
            return b""
        return self.rfile.read(length)

    def _json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self._cors_headers()
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _cors_headers(self):
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-methods", "GET, POST, OPTIONS")
        self.send_header("access-control-allow-headers", "content-type, accept")


def main():
    server = HTTPServer((HOST, PORT), GatewayHandler)
    print(f"AI Gateway listening on http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
