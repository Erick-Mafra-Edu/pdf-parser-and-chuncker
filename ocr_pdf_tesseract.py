# Requer: pip install pdf2image pytesseract pillow
# Também precisa do Tesseract OCR instalado no sistema (tesseract).
# Uso: python ocr_pdf_tesseract.py input.pdf output.txt
import sys
from pdf2image import convert_from_path
import pytesseract

def ocr_pdf(input_pdf, output_txt, dpi=300):
    pages = convert_from_path(input_pdf, dpi=dpi)
    with open(output_txt, "w", encoding="utf-8") as out:
        for i, img in enumerate(pages, start=1):
            out.write(f"\n\n=== PAGE {i} (OCR) ===\n\n")
            text = pytesseract.image_to_string(img, lang='por+eng')  # ajustar idiomas conforme necessário
            out.write(text)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python ocr_pdf_tesseract.py input.pdf output.txt")
    else:
        ocr_pdf(sys.argv[1], sys.argv[2])