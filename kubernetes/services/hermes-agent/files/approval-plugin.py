"""Hermes slash commands for exact policy-gateway approvals."""

import json
import asyncio
import logging
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import re
import urllib.error
import urllib.parse
import urllib.request

_ACTION_ID = re.compile(r"^[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{16}$")
_BASE_URL = "http://127.0.0.1:8090/approvals"


def _format_card(card, expires):
    operation = "Create Wiki page?" if card["operation"] == "create" else "Update Wiki page?"
    parts = [operation, f"{card['title'][:250]}\n{card['path'][:300]}",
             "Proposed content\n" + str(card.get("content_preview", ""))[:1201]]
    description = str(card.get("description") or "")
    if description:
        parts.append("Proposed page description\n" + description[:300])
    tags = ", ".join(card.get("tags") or [])
    if tags:
        parts.append("Tags: " + tags[:200])
    local = expires.astimezone(ZoneInfo("Europe/Helsinki"))
    parts.append(f"Nothing has changed yet.\nApprove by {local:%H:%M} (Helsinki).")
    return "\n\n".join(parts)


def _preview(result):
    """Accept only a structured gateway staging result, never model prose."""
    for _ in range(4):
        if isinstance(result, str):
            try:
                result = json.loads(result)
            except (ValueError, TypeError):
                return None
        if not isinstance(result, dict) or result.get("isError") or result.get("error"):
            return None
        if result.get("status") == "awaiting_approval":
            if not _ACTION_ID.fullmatch(str(result.get("action_id", ""))):
                return None
            if result.get("operation") not in ("create", "update"):
                return None
            return result
        if "content" in result and isinstance(result["content"], list):
            blocks = result["content"]
            if len(blocks) != 1 or blocks[0].get("type") != "text":
                return None
            result = blocks[0].get("text")
        elif "result" in result:
            result = result["result"]
        else:
            return None
    return None


class ApprovalButtons:
    def __init__(self):
        self.loop = None
        self.app = None
        self.adapter = None
        self.pending = {}

    def wire(self, application, adapter):
        from telegram.ext import CallbackQueryHandler
        self.loop = asyncio.get_running_loop()
        self.app, self.adapter = application, adapter
        application.add_handler(CallbackQueryHandler(self.on_button, pattern=r"^hpa:"))

    def is_admin(self, user_id):
        return str(user_id) in {str(x) for x in self.adapter.config.extra.get("allow_admin_from", [])}

    def after_tool(self, tool_name="", result=None, **kwargs):
        if tool_name not in ("mcp__knowledge_base__wiki_stage_create", "mcp__knowledge_base__wiki_stage_update"):
            return
        from gateway.session_context import get_session_env
        if not self.loop or get_session_env("HERMES_SESSION_PLATFORM") != "telegram":
            return
        card = _preview(result)
        chat = get_session_env("HERMES_SESSION_CHAT_ID")
        user = get_session_env("HERMES_SESSION_USER_ID")
        if not card or not chat or chat != user or not self.is_admin(user):
            return
        thread = get_session_env("HERMES_SESSION_THREAD_ID")
        future = asyncio.run_coroutine_threadsafe(self.send_card(card, chat, user, thread), self.loop)
        def done(f):
            try:
                f.result()
            except Exception:
                logging.getLogger(__name__).exception("Approval card delivery failed; slash commands remain available")
        future.add_done_callback(done)

    async def send_card(self, card, chat, user, thread=""):
        from telegram import InlineKeyboardButton, InlineKeyboardMarkup
        now = datetime.now(timezone.utc)
        self.pending = {key: value for key, value in self.pending.items() if value["expires"] > now}
        action_id = card["action_id"]
        expires = datetime.fromisoformat(card["expires_at"].replace("Z", "+00:00"))
        if action_id in self.pending or expires <= now:
            return
        text = _format_card(card, expires)
        # Telegram counts UTF-16 units; keep non-BMP page content within limits.
        text = text.encode("utf-16-le")[:7800].decode("utf-16-le", errors="ignore")
        keyboard = InlineKeyboardMarkup([[
            InlineKeyboardButton("Approve", callback_data="hpa:a:" + action_id),
            InlineKeyboardButton("Deny", callback_data="hpa:d:" + action_id),
        ]])
        entry = {"chat": str(chat), "user": str(user), "expires": expires, "message": None, "text": text}
        self.pending[action_id] = entry
        try:
            message = await self.app.bot.send_message(chat_id=chat, text=text, reply_markup=keyboard,
                **({"message_thread_id": int(thread)} if thread else {}))
            entry["message"] = message.message_id
        except Exception:
            self.pending.pop(action_id, None)
            raise

    async def on_button(self, update, context):
        query = update.callback_query
        parts = (query.data or "").split(":", 2)
        if len(parts) != 3 or parts[1] not in ("a", "d") or not _ACTION_ID.fullmatch(parts[2]):
            await query.answer("Invalid approval button.")
            return
        action_id = parts[2]
        entry = self.pending.get(action_id)
        message = query.message
        user = str(query.from_user.id)
        if not entry:
            await query.answer("Expired or already resolved. Ask Hermes for a fresh preview.", show_alert=True)
            return
        if (not message or str(message.chat_id) != entry["chat"] or message.message_id != entry["message"]
                or user != entry["user"] or not self.is_admin(user)
                or not self.adapter._is_callback_user_authorized(user, chat_id=entry["chat"], chat_type="private")):
            await query.answer("You cannot approve this change.", show_alert=True)
            return
        # Consume before awaiting network I/O, so double clicks cannot execute twice.
        self.pending.pop(action_id)
        await query.answer("Processing…")
        if entry["expires"] <= datetime.now(timezone.utc):
            result = "Expired. Ask Hermes for a fresh preview."
        else:
            result = await asyncio.to_thread(_decide, action_id, "approve" if parts[1] == "a" else "deny")
        await query.edit_message_text(text=entry["text"][:3000] + "\n\nResult: " + result[:900], reply_markup=None)


def _decide(raw_args: str, decision: str) -> str:
    action_id = raw_args.strip()
    if not _ACTION_ID.fullmatch(action_id):
        return f"Usage: /{decision}_action <action-id>"

    safe_id = urllib.parse.quote(action_id, safe=".-_")
    request = urllib.request.Request(
        f"{_BASE_URL}/{safe_id}/{decision}",
        data=b"",
        method="POST",
        headers={"Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            body = json.load(exc)
            return str(body.get("message", "Approval failed"))
        except Exception:
            return f"Approval failed with HTTP {exc.code}"
    except Exception as exc:
        return f"Approval gateway unavailable: {exc}"
    return str(body.get("message", "Decision recorded"))


def register(ctx):
    buttons = ApprovalButtons()
    ctx.register_telegram_handler(buttons.wire)
    ctx.register_hook("post_tool_call", buttons.after_tool)
    # Hermes maps Telegram underscores to hyphens before plugin lookup.
    ctx.register_command(
        "approve-action",
        handler=lambda raw_args: _decide(raw_args, "approve"),
        description="Approve one exact staged external action",
    )
    ctx.register_command(
        "deny-action",
        handler=lambda raw_args: _decide(raw_args, "deny"),
        description="Deny one staged external action",
    )
