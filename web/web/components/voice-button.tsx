"use client";

import { Mic, Square } from "lucide-react";

type Props = {
  recording: boolean;
  onToggle: () => void;
  label: string;
};

export function VoiceButton({ recording, onToggle, label }: Props) {
  return (
    <button
      type="button"
      onClick={onToggle}
      style={{
        height: 52,
        width: 52,
        borderRadius: 18,
        border: "1px solid rgba(24,50,43,0.12)",
        background: recording ? "#18322b" : "rgba(255,255,255,0.92)",
        color: recording ? "white" : "#18322b",
        cursor: "pointer"
      }}
      aria-label={label}
      title={label}
    >
      {recording ? <Square size={18} /> : <Mic size={18} />}
    </button>
  );
}
