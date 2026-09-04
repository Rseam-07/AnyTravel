import { useEffect, useRef, useState } from "react";
import { Send, Sparkles, X } from "lucide-react";
import { useApp } from "../store";

interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}

const SUGGESTIONS = [
  "苏州3天2人，预算每人3000，松弛一点",
  "改成2天，带娃，多选亲子",
  "去程从上海出发，预算2000"
];

export default function ChatPanel() {
  const { state, chatStream, sendChat, closeChat } = useChatBridge();
  const [messages, setMessages] = useState<Message[]>([
    {
      role: "assistant",
      content: "可以直接说：目的地、日期、天数、人数、预算、节奏、兴趣与交通；我会把确定的部分落回地图，不确定的会问你再排班。"
    }
  ]);
  const [input, setInput] = useState("");
  const scrollRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, chatStream]);

  const send = async (text?: string) => {
    const content = (text ?? input).trim();
    if (!content) return;
    setInput("");
    setMessages((prev) => [...prev, { role: "user", content }]);
    try {
      const answer = await sendChat(content);
      if (answer) {
        setMessages((prev) => [...prev, { role: "assistant", content: answer }]);
      }
    } catch (error) {
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: `（暂时没能连上：${error instanceof Error ? error.message : String(error)}）` }
      ]);
    }
  };

  const busy = state.chatBusy;

  return (
    <div className="chat-panel">
      <div className="chat-head">
        <span><Sparkles size={17} aria-hidden="true" />智能向导</span>
        <button className="chat-close" onClick={closeChat} aria-label="关闭对话">
          <X size={18} aria-hidden="true" />
        </button>
      </div>
      <div className="chat-messages" ref={scrollRef}>
        {messages.map((message, index) => (
          <div key={index} className={`chat-msg ${message.role}`}>
            {message.content}
          </div>
        ))}
        {chatStream != null && <div className="chat-msg assistant">{chatStream || "…"}</div>}
        {busy && chatStream == null && <div className="chat-msg assistant">思考中…</div>}
        {!state.backendReachable && !state.settings.deepseekKey && (
          <div className="chat-msg system">智能服务未连接；天数、人数、预算、节奏和常见目的地仍可在本机识别。</div>
        )}
      </div>
      {messages.length <= 1 && (
        <div className="chat-suggestions">
          {SUGGESTIONS.map((s) => (
            <button key={s} className="chip-btn" onClick={() => void send(s)}>
              {s}
            </button>
          ))}
        </div>
      )}
      <div className="chat-input-row">
        <input
          value={input}
          aria-label="告诉智能向导你的旅行需求"
          placeholder="比如：苏州 3 天 2 人，带爸妈，预算每人 2500"
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !busy) void send();
          }}
        />
        <button className="chat-send" disabled={busy} onClick={() => void send()} aria-label="发送">
          <Send size={18} aria-hidden="true" />
        </button>
      </div>
    </div>
  );
}

function useChatBridge() {
  const app = useApp();
  return {
    state: app.state,
    chatStream: app.chatStream,
    sendChat: app.sendChat,
    closeChat: () => app.toggleChat(false)
  };
}
