<#
.SYNOPSIS
  Percorre uma pasta, e para cada PDF encontrado executa os scripts Python:
    - extract_text_pdfplumber.py
    - (condicional) ocr_pdf_tesseract.py
    - chunk_for_model.py

.DESCRIPTION
  O script assume que os scripts Python estão em $ScriptsDir (por padrão o diretório atual).
  Para cada PDF ele:
    1. Extrai texto com extract_text_pdfplumber.py -> <basename>.txt
    2. Se o texto extraído indicar páginas sem texto (marca "[NO TEXT ON PAGE - POSSIBLE SCAN/IMAGE PAGE]") 
       ou se passar -ForceOCR, executa ocr_pdf_tesseract.py -> <basename>.ocr.txt
    3. Executa chunk_for_model.py usando o arquivo de texto apropriado -> <basename>.chunks.jsonl
    4. Grava logs por PDF em uma pasta dedicada ($OutputDir\<basename>)

.PARAMETER SourceDir
  Pasta onde procurar PDFs (padrão: .\pdfs)

.PARAMETER ScriptsDir
  Pasta onde estão os scripts Python (padrão: diretório atual)

.PARAMETER OutputDir
  Pasta raiz onde serão gravados os resultados (padrão: .\output)

.PARAMETER PythonExe
  Caminho/nomedo executável Python (padrão: python)

.PARAMETER ChunkTokens
  Tokens por chunk para chunk_for_model.py (padrão: 1500)

.PARAMETER Overlap
  Tokens de overlap entre chunks (padrão: 200)

.PARAMETER ForceOCR
  Se setado, sempre executa OCR mesmo que o extractor encontre texto.

.EXAMPLE
  .\process_pdfs.ps1 -SourceDir "C:\meus_pdfs" -ScriptsDir "C:\meus_scripts" -OutputDir "C:\saida" -PythonExe "C:\Python39\python.exe"

REQUIRES
  - Python no PATH ou passe via -PythonExe
  - Pacotes Python: pdfplumber, pdf2image, pytesseract, Pillow, tiktoken (veja requirements.txt)
  - Tesseract OCR instalado (e poppler para pdf2image)
#>

param(
    [Parameter(Position=0)]
    [string]$SourceDir = ".\pdfs",

    [string]$ScriptsDir = ".",

    [string]$OutputDir = ".\output",

    [string]$PythonExe = "python",

    [int]$ChunkTokens = 1500,

    [int]$Overlap = 200,

    [switch]$ForceOCR
)

Set-StrictMode -Version Latest

function Write-Log {
    param($Path, $Message)
    $ts = (Get-Date).ToString("s")
    "$ts`t$Message" | Out-File -FilePath $Path -Encoding utf8 -Append
}

function Run-Python {
    param(
        [string]$ScriptRelative,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $ScriptsDir $ScriptRelative
    if (-not (Test-Path $scriptPath)) {
        return @{ Success = $false; ExitCode = -1; StdOut = ""; StdErr = "Script not found: $scriptPath" }
    }

    # montar argumentos protegendo caminhos com espaços
    $escapedArgs = $Arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' } 
    $argLine = ($escapedArgs -join " ")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PythonExe
    $psi.Arguments = "`"$scriptPath`" $argLine"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        return @{ Success = $false; ExitCode = -1; StdOut = ""; StdErr = "Failed to start Python: $($_.Exception.Message)" }
    }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return @{ Success = ($proc.ExitCode -eq 0); ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

# Verifica diretórios
if (-not (Test-Path $SourceDir)) {
    Write-Error "SourceDir não existe: $SourceDir"
    exit 1
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Enumerar PDFs recursivamente
$pdfs = Get-ChildItem -Path $SourceDir -Filter *.pdf -Recurse -File

if ($pdfs.Count -eq 0) {
    Write-Output "Nenhum PDF encontrado em $SourceDir"
    exit 0
}

foreach ($pdf in $pdfs) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($pdf.Name)
    $outSub = Join-Path $OutputDir $base
    New-Item -ItemType Directory -Path $outSub -Force | Out-Null

    $txtPath = Join-Path $outSub "$base.txt"
    $ocrPath = Join-Path $outSub "$base.ocr.txt"
    $chunksPath = Join-Path $outSub "$base.chunks.jsonl"
    $logPath = Join-Path $outSub "log.txt"

    Write-Log $logPath "Processing PDF: $($pdf.FullName)"

    # 1) Extrair texto com pdfplumber
    Write-Log $logPath "Running extract_text_pdfplumber.py"
    $r1 = Run-Python "extract_text_pdfplumber.py" @($pdf.FullName, $txtPath)
    if ($r1.StdOut) { $r1.StdOut | Out-File -FilePath (Join-Path $outSub "extract_stdout.txt") -Encoding utf8 }
    if ($r1.StdErr) { $r1.StdErr | Out-File -FilePath (Join-Path $outSub "extract_stderr.txt") -Encoding utf8 }
    Write-Log $logPath "extract exit: $($r1.ExitCode)"

    # Verificar se precisamos executar OCR:
    $needOCR = $false
    if ($ForceOCR.IsPresent) {
        $needOCR = $true
        Write-Log $logPath "ForceOCR set -> will run OCR"
    } else {
        if (-not (Test-Path $txtPath)) {
            $needOCR = $true
            Write-Log $logPath "No extracted text file produced -> will run OCR"
        } else {
            # procurar marcador de página sem texto
            $content = Get-Content -Raw -Encoding utf8 $txtPath
            if ($content -match "\[NO TEXT ON PAGE - POSSIBLE SCAN/IMAGE PAGE\]") {
                $needOCR = $true
                Write-Log $logPath "Extractor flagged pages without text -> will run OCR"
            } elseif ($content.Trim().Length -eq 0) {
                $needOCR = $true
                Write-Log $logPath "Extracted text is empty -> will run OCR"
            } else {
                Write-Log $logPath "Extracted text found, skipping OCR"
            }
        }
    }

    if ($needOCR) {
        Write-Log $logPath "Running ocr_pdf_tesseract.py"
        $r2 = Run-Python "ocr_pdf_tesseract.py" @($pdf.FullName, $ocrPath)
        if ($r2.StdOut) { $r2.StdOut | Out-File -FilePath (Join-Path $outSub "ocr_stdout.txt") -Encoding utf8 }
        if ($r2.StdErr) { $r2.StdErr | Out-File -FilePath (Join-Path $outSub "ocr_stderr.txt") -Encoding utf8 }
        Write-Log $logPath "ocr exit: $($r2.ExitCode)"
    }

    # Escolher qual arquivo de texto usar para chunking:
    $useText = $null
    if ((Test-Path $ocrPath) -and ((Get-Content -Raw -Encoding utf8 $ocrPath).Trim().Length -gt 0) -and $needOCR) {
        $useText = $ocrPath
        Write-Log $logPath "Using OCR text for chunking: $ocrPath"
    } elseif (Test-Path $txtPath) {
        $useText = $txtPath
        Write-Log $logPath "Using extracted text for chunking: $txtPath"
    } else {
        Write-Log $logPath "No text available for chunking. Skipping chunk_for_model."
    }

    # 3) Chunking
    if ($useText) {
        Write-Log $logPath "Running chunk_for_model.py"
        $r3 = Run-Python "chunk_for_model.py" @($useText, $chunksPath, "--chunk_tokens", $ChunkTokens.ToString(), "--overlap", $Overlap.ToString())
        if ($r3.StdOut) { $r3.StdOut | Out-File -FilePath (Join-Path $outSub "chunk_stdout.txt") -Encoding utf8 }
        if ($r3.StdErr) { $r3.StdErr | Out-File -FilePath (Join-Path $outSub "chunk_stderr.txt") -Encoding utf8 }
        Write-Log $logPath "chunk exit: $($r3.ExitCode)"
    }

    Write-Log $logPath "Finished processing $($pdf.Name)"
    Write-Output "Processed: $($pdf.FullName) -> $outSub"
}

Write-Output "All done. Output folder: $OutputDir"