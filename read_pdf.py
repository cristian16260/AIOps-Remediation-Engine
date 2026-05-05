import sys
import subprocess
import os

pdf_path = os.path.join("c:\\Proyectos\\aiops-remediation-engine", "AIOps Remediation Engine.pdf")
out_path = os.path.join("c:\\Proyectos\\aiops-remediation-engine", "pdf_text.txt")

try:
    import pypdf
except ImportError:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'pypdf'])
    import pypdf

try:
    reader = pypdf.PdfReader(pdf_path)
    text = ""
    for page in reader.pages:
        text += page.extract_text() + "\n"

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
    print("Extracted PDF to pdf_text.txt")
except Exception as e:
    print(f"Error reading PDF: {e}")
