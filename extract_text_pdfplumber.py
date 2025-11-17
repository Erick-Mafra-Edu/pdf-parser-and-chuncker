# Requer: pip install pdfplumber
# Uso: python extract_text_pdfplumber.py input.pdf output.txt
import sys
import pdfplumber

def extract(input_pdf, output_txt):
    with pdfplumber.open(input_pdf) as pdf, open(output_txt, "w", encoding="utf-8") as out:
        for i, page in enumerate(pdf.pages, start=1):
            text = page.extract_text()
            out.write(f"\n\n=== PAGE {i} ===\n\n")
            if text:
                out.write(text)
            else:
                out.write("[NO TEXT ON PAGE - POSSIBLE SCAN/IMAGE PAGE]\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python extract_text_pdfplumber.py input.pdf output.txt")
    else:
        extract(sys.argv[1], sys.argv[2])