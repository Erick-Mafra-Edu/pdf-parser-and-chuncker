# Processo recomendado para colocar PDF no contexto do modelo

1. Se o PDF contiver texto pesquisável:
   - Rode `extract_text_pdfplumber.py input.pdf output.txt`.
2. Se o PDF for escaneado (imagens):
   - Instale Tesseract e rode `ocr_pdf_tesseract.py input.pdf output.txt`.
3. Em seguida, divida o texto em chunks para o modelo:
   - Rode `chunk_for_model.py output.txt chunks.jsonl --chunk_tokens 1500 --overlap 200`
   - Ajuste `--chunk_tokens` conforme o tamanho de contexto do modelo (ex.: 4k, 8k, 32k tokens).
4. Opções:
   - Se for gerar embeddings, use cada chunk como um documento (JSONL).
   - Inclua metadados (página, título, seção) quando possível.
   - Limpe caracteres de controle e repita limpeza de espaços.
5. Se quiser, eu posso:
   - Converter se você subir o PDF aqui;
   - Gerar prompts para uso direto com os chunks;
   - Resumir cada chunk e produzir um "contexto curto" para prompt.

# Dependências
- python3
- pip install pdfplumber pdf2image pytesseract pillow tiktoken
- Tesseract OCR (para OCR)