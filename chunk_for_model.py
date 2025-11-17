# Requer: pip install tiktoken
# Uso: python chunk_for_model.py full_text.txt chunks.jsonl --chunk_tokens 1500 --overlap 200
import sys
import json
import argparse
import tiktoken

def load_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def split_sentences(text):
    # Simples: quebra por parágrafos
    paras = [p.strip() for p in text.split("\n\n") if p.strip()]
    return paras

def chunk_by_tokens(paragraphs, encoder, max_tokens, overlap):
    chunks = []
    cur = ""
    cur_tokens = 0
    for p in paragraphs:
        p_tokens = len(encoder.encode(p))
        if cur_tokens + p_tokens <= max_tokens:
            if cur:
                cur += "\n\n" + p
            else:
                cur = p
            cur_tokens = len(encoder.encode(cur))
        else:
            # flush cur
            chunks.append(cur)
            # start new with overlap: take last 'overlap' tokens from cur and prepend?
            # Simple approach: start new with p
            cur = p
            cur_tokens = p_tokens
            # if paragraph alone > max_tokens, force-split naive
            if p_tokens > max_tokens:
                toks = encoder.encode(p)
                i = 0
                while i < len(toks):
                    piece = encoder.decode(toks[i:i+max_tokens])
                    chunks.append(piece)
                    i += max_tokens - overlap
                cur = ""
                cur_tokens = 0
    if cur:
        chunks.append(cur)
    return chunks

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="plain text input file")
    parser.add_argument("output", help="jsonl output")
    parser.add_argument("--chunk_tokens", type=int, default=1500)
    parser.add_argument("--overlap", type=int, default=200)
    parser.add_argument("--model", type=str, default="gpt-4o-mini")  # só para escolher encoding; ajuste se necessário
    args = parser.parse_args()

    text = load_text(args.input)
    paras = split_sentences(text)
    # escolher encoding: usar cl100k_base para OpenAI-ish models; tiktoken auto
    try:
        enc = tiktoken.encoding_for_model(args.model)
    except:
        enc = tiktoken.get_encoding("cl100k_base")
    chunks = chunk_by_tokens(paras, enc, args.chunk_tokens, args.overlap)
    with open(args.output, "w", encoding="utf-8") as out:
        for i, c in enumerate(chunks):
            record = {"id": f"{args.input}#chunk-{i+1}", "text": c, "tokens": len(enc.encode(c)), "chunk_index": i+1}
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(f"Wrote {len(chunks)} chunks to {args.output}")

if __name__ == "__main__":
    main()