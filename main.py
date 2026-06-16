import base64
import gzip
import random
import secrets
import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.padding import PKCS7

PROJECT_URL = "https://github.com/rvsh3ll/powershell-encrypter"
_DEFAULT_VERSION = "v1.0.1"
_version_path = Path(__file__).with_name("VERSION")
VERSION = (
    _version_path.read_text(encoding="utf-8").strip()
    if _version_path.is_file()
    else _DEFAULT_VERSION
)


def get_random_bytes(length: int) -> bytes:
    return secrets.token_bytes(length)


def compress_bytes(data: bytes) -> bytes:
    return gzip.compress(data)


def protect_aes_bytes(plaintext: bytes, key: bytes, iv: bytes) -> bytes:
    padder = PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    return encryptor.update(padded) + encryptor.finalize()


def protect_key_material_with_password(key_material: bytes, password: str) -> dict:
    salt = get_random_bytes(16)
    wrap_iv = get_random_bytes(16)
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA1(),
        length=32,
        salt=salt,
        iterations=100_000,
    )
    wrap_key = kdf.derive(password.encode("utf-8"))
    wrapped_key = protect_aes_bytes(key_material, wrap_key, wrap_iv)
    return {
        "wrapped_key": wrapped_key,
        "salt": salt,
        "wrap_iv": wrap_iv,
    }


def split_byte_array_into_chunks(
    data: bytes,
    min_chunk: int = 48,
    max_chunk: int = 128,
) -> list[bytes]:
    if not data:
        return []

    chunks: list[bytes] = []
    index = 0
    while index < len(data):
        remaining = len(data) - index
        max_len = min(max_chunk, remaining)
        min_len = min(min_chunk, max_len)
        if min_len < 1:
            min_len = 1
        length = max_len if max_len == min_len else random.randint(min_len, max_len)

        chunks.append(data[index : index + length])
        index += length

    return chunks


def new_decoy_byte_chunks(count: int = 2) -> list[bytes]:
    return [get_random_bytes(random.randint(24, 95)) for _ in range(count)]


def build_scattered_chunks(
    real_chunks: list[bytes],
    decoy_count: int,
) -> dict[str, list]:
    decoys = new_decoy_byte_chunks(decoy_count)
    total_slots = len(real_chunks) + len(decoys)
    slots = list(range(total_slots))
    random.shuffle(slots)

    array: list[bytes | None] = [None] * total_slots
    order: list[int] = []

    real_slots = sorted(slots[: len(real_chunks)])
    for index, slot in enumerate(real_slots):
        array[slot] = real_chunks[index]
        order.append(slot)

    decoy_slots = slots[len(real_chunks) :]
    for index, slot in enumerate(decoy_slots):
        array[slot] = decoys[index]

    return {"chunks": array, "order": order}


def format_byte_array_literal(data: bytes) -> str:
    return ",".join(f"0x{byte:02X}" for byte in data)


def format_byte_chunk_arrays_literal(chunks: list) -> str:
    formatted = [
        "[byte[]]@(" + format_byte_array_literal(bytes(chunk)) + ")"
        for chunk in chunks
    ]
    return ",".join(formatted)


def convert_to_encrypted_package(data: bytes, password: str) -> dict:
    compressed = compress_bytes(data)
    key = get_random_bytes(32)
    iv = get_random_bytes(16)

    ciphertext = protect_aes_bytes(compressed, key, iv)

    key_material = key + iv
    wrapped = protect_key_material_with_password(key_material, password)

    cipher_split = build_scattered_chunks(
        split_byte_array_into_chunks(ciphertext),
        random.randint(2, 3),
    )
    key_split = build_scattered_chunks(
        split_byte_array_into_chunks(wrapped["wrapped_key"]),
        random.randint(2, 3),
    )

    return {
        "cipher_chunks": cipher_split["chunks"],
        "cipher_order": cipher_split["order"],
        "key_chunks": key_split["chunks"],
        "key_order": key_split["order"],
        "salt": wrapped["salt"],
        "wrap_iv": wrapped["wrap_iv"],
    }


def format_startup_message_literal(message: str) -> str:
    if not message:
        return ""
    return base64.b64encode(message.encode("utf-8")).decode("ascii")


def get_ps1_wrapper(
    package: dict,
    startup_message: str = "",
    message_display: str = "box",
    password_prompt: str = "box",
    use_blank_password: bool = False,
) -> str:
    cipher_order_literal = ",".join(str(value) for value in package["cipher_order"])
    key_order_literal = ",".join(str(value) for value in package["key_order"])
    cipher_chunks_literal = format_byte_chunk_arrays_literal(package["cipher_chunks"])
    key_chunks_literal = format_byte_chunk_arrays_literal(package["key_chunks"])
    salt_literal = format_byte_array_literal(package["salt"])
    wrap_iv_literal = format_byte_array_literal(package["wrap_iv"])
    startup_message_literal = format_startup_message_literal(startup_message)
    message_display_mode = "console" if message_display == "console" else "box"
    password_prompt_mode = "console" if password_prompt == "console" else "box"
    use_blank_password_flag = "1" if use_blank_password else "0"

    lines = [
        "#requires -Version 5.1",
        "param([string]$Password='')",
        "$ErrorActionPreference='Stop'",
        f"$a1=@({cipher_order_literal})",
        f"$a2=@({cipher_chunks_literal})",
        f"$a3=@({key_order_literal})",
        f"$a4=@({key_chunks_literal})",
        f"$a5=@({salt_literal})",
        f"$a6=@({wrap_iv_literal})",
        f"$m0='{startup_message_literal}'",
        f"$m1='{message_display_mode}'",
        f"$m2='{password_prompt_mode}'",
        f"$m3={use_blank_password_flag}",
        "$b1={param($o,$c)$len=0;0..($o.Length-1)|ForEach-Object{$len+=$c[$o[$_]].Length};$out=New-Object byte[] $len;$p=0;0..($o.Length-1)|ForEach-Object{$ch=[byte[]]$c[$o[$_]];[Array]::Copy($ch,0,$out,$p,$ch.Length);$p+=$ch.Length};$out}",
        "$b3='System.Security'",
        "$b4='System.IO.Compression'",
        "$b5='System.Windows.Forms'",
        "Add-Type -AssemblyName $b3",
        "Add-Type -AssemblyName $b4",
        f"$b6='{PROJECT_URL}'",
        f"$b7='{VERSION}'",
        "Write-Output $b6",
        "Write-Output $b7",
        "if(-not [string]::IsNullOrEmpty($m0)){$msg=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m0));if($m1 -eq 'console'){Write-Output $msg}else{Add-Type -AssemblyName $b5;[System.Windows.Forms.MessageBox]::Show($msg,'Message',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)|Out-Null}}",
        "$p1=& $b1 $a1 $a2",
        "$w1=& $b1 $a3 $a4",
        "if($Password -eq ' '){}elseif([string]::IsNullOrEmpty($Password)){if($m3 -eq 1){$Password=' '}elseif($m2 -eq 'console'){$q=Read-Host -AsSecureString 'Password';$z=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($q);try{$Password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($z)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($z)}}else{Add-Type -AssemblyName $b5;$f=New-Object System.Windows.Forms.Form;$f.Text='Password';$f.Width=380;$f.Height=150;$f.FormBorderStyle='FixedDialog';$f.StartPosition='CenterScreen';$f.MaximizeBox=$false;$f.MinimizeBox=$false;$f.TopMost=$true;$l=New-Object System.Windows.Forms.Label;$l.Text='Enter password:';$l.AutoSize=$true;$l.Left=12;$l.Top=18;$f.Controls.Add($l);$t=New-Object System.Windows.Forms.TextBox;$t.UseSystemPasswordChar=$true;$t.Width=330;$t.Left=12;$t.Top=42;$f.Controls.Add($t);$b=New-Object System.Windows.Forms.Button;$b.Text='OK';$b.Width=90;$b.Left=170;$b.Top=78;$b.DialogResult=[System.Windows.Forms.DialogResult]::OK;$f.Controls.Add($b);$f.AcceptButton=$b;$c=New-Object System.Windows.Forms.Button;$c.Text='Cancel';$c.Width=90;$c.Left=252;$c.Top=78;$c.DialogResult=[System.Windows.Forms.DialogResult]::Cancel;$f.Controls.Add($c);$f.CancelButton=$c;if($f.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){return};$Password=$t.Text;$f.Dispose()}}",
        "$z1=[Text.Encoding]::UTF8.GetBytes($Password)",
        "$z2=New-Object Security.Cryptography.Rfc2898DeriveBytes($z1,$a5,100000)",
        "$z3=$z2.GetBytes(32)",
        "$z2.Dispose()",
        "$c0=[Security.Cryptography.Aes]::Create()",
        "$c0.Key=$z3",
        "$c0.IV=$a6",
        "$c0.Mode=[Security.Cryptography.CipherMode]::CBC",
        "$c0.Padding=[Security.Cryptography.PaddingMode]::PKCS7",
        "$k1=$c0.CreateDecryptor().TransformFinalBlock($w1,0,$w1.Length)",
        "$k2=New-Object byte[] 32",
        "$k3=New-Object byte[] 16",
        "[Array]::Copy($k1,0,$k2,0,32)",
        "[Array]::Copy($k1,32,$k3,0,16)",
        "$c1=[Security.Cryptography.Aes]::Create()",
        "$c1.Key=$k2",
        "$c1.IV=$k3",
        "$c1.Mode=[Security.Cryptography.CipherMode]::CBC",
        "$c1.Padding=[Security.Cryptography.PaddingMode]::PKCS7",
        "$p2=$c1.CreateDecryptor().TransformFinalBlock($p1,0,$p1.Length)",
        "$m1=New-Object IO.MemoryStream(,$p2)",
        "$m2=New-Object IO.Compression.GzipStream($m1,[IO.Compression.CompressionMode]::Decompress)",
        "$m3=New-Object IO.MemoryStream",
        "$m2.CopyTo($m3)",
        "$t1=[Text.Encoding]::UTF8.GetString($m3.ToArray())",
        "$r1=$PSScriptRoot",
        "if([string]::IsNullOrEmpty($r1) -and $MyInvocation.MyCommand.Path){$r1=Split-Path -Parent $MyInvocation.MyCommand.Path}",
        "$r2=$MyInvocation.MyCommand.Path",
        "if([string]::IsNullOrEmpty($r2)){$r2=$PSCommandPath}",
        '$s1=[ScriptBlock]::Create("param([string]`$PSScriptRoot,[string]`$PSCommandPath)`n"+$t1)',
        "& $s1 -PSScriptRoot $r1 -PSCommandPath $r2",
    ]
    return "\r\n".join(lines)


def save_encrypted_ps1(
    path: str,
    package: dict,
    startup_message: str = "",
    message_display: str = "box",
    password_prompt: str = "box",
    use_blank_password: bool = False,
) -> None:
    content = get_ps1_wrapper(
        package,
        startup_message,
        message_display,
        password_prompt,
        use_blank_password,
    )
    with open(path, "w", encoding="utf-8", newline="\r\n") as file:
        file.write(content)


def open_saved_file_folder(file_path: str) -> None:
    path = Path(file_path)
    if path.is_file():
        subprocess.run(["explorer", f"/select,{path.resolve()}"], check=False)
        return
    if path.parent.is_dir():
        subprocess.run(["explorer", str(path.parent.resolve())], check=False)


def encrypt_script(settings: dict[str, str | bool]) -> tuple[bool, str, str]:
    try:
        with open(settings["input_path"], "rb") as file:
            data = file.read()

        package = convert_to_encrypted_package(data, settings["password"])
        save_encrypted_ps1(
            settings["output_path"],
            package,
            settings["startup_message"],
            settings["message_display"],
            settings["password_prompt"],
            settings["use_blank_password"],
        )
        return True, "Success", str(settings["output_path"])
    except OSError as error:
        return False, "File error", str(error)
    except Exception as error:
        return False, "Encryption failed", str(error)


def show_encryption_form() -> None:
    print(f"PowerShell Script Encryptor {VERSION}")
    print(PROJECT_URL)

    root = tk.Tk()
    root.title(f"PowerShell Script Encryptor {VERSION}")
    root.geometry("524x472")
    root.resizable(False, False)

    input_var = tk.StringVar()
    output_var = tk.StringVar()
    password_var = tk.StringVar()
    message_display_var = tk.StringVar(value="console")
    password_prompt_var = tk.StringVar(value="console")

    def browse_input() -> None:
        path = filedialog.askopenfilename(
            title="Select file to encrypt",
            filetypes=[
                ("PowerShell scripts", "*.ps1"),
                ("All files", "*.*"),
            ],
        )
        if path:
            input_var.set(path)

    def browse_output() -> None:
        path = filedialog.asksaveasfilename(
            title="Save encrypted file",
            defaultextension=".enc.ps1",
            filetypes=[
                ("Encrypted PowerShell", "*.enc.ps1"),
                ("PowerShell scripts", "*.ps1"),
                ("All files", "*.*"),
            ],
        )
        if path:
            output_var.set(path)

    def on_encrypt() -> None:
        input_path = input_var.get().strip()
        output_path = output_var.get().strip()
        password_text = password_var.get()

        if not input_path:
            messagebox.showwarning("Validation", "Please select an input file.")
            return
        if not Path(input_path).is_file():
            messagebox.showwarning("Validation", "The input file does not exist.")
            return
        if not output_path:
            messagebox.showwarning("Validation", "Please select an output file.")
            return

        use_blank_password = password_text == ""
        password = " " if use_blank_password else password_text

        settings = {
            "input_path": input_path,
            "output_path": output_path,
            "startup_message": startup_box.get("1.0", "end-1c"),
            "password": password,
            "use_blank_password": use_blank_password,
            "message_display": message_display_var.get(),
            "password_prompt": password_prompt_var.get(),
        }

        success, title, message = encrypt_script(settings)
        if success:
            messagebox.showinfo(
                title,
                f"Encrypted file saved to:\n{message}\n\n"
                "To run it:\n"
                f'powershell -ExecutionPolicy Bypass -File "{message}"',
            )
            open_saved_file_folder(message)
            return

        messagebox.showerror(title, message)

    def on_cancel() -> None:
        root.destroy()

    padding = 16
    field_width = 48
    browse_x = 412

    tk.Label(root, text="Input file:").place(x=padding, y=14)
    tk.Entry(root, textvariable=input_var, width=field_width, state="readonly").place(x=padding, y=34)
    tk.Button(root, text="Browse...", width=11, command=browse_input).place(x=browse_x, y=33)

    tk.Label(root, text="Output file:").place(x=padding, y=66)
    tk.Entry(root, textvariable=output_var, width=field_width, state="readonly").place(x=padding, y=86)
    tk.Button(root, text="Browse...", width=11, command=browse_output).place(x=browse_x, y=85)

    tk.Label(
        root,
        text="Startup message (optional, multiple lines supported):",
        anchor="w",
    ).place(x=padding, y=118, width=492)
    startup_box = tk.Text(root, width=58, height=5, wrap="word")
    startup_box.place(x=padding, y=138)

    message_group = tk.LabelFrame(root, text="Show startup message via")
    message_group.place(x=padding, y=238, width=240, height=56)
    tk.Radiobutton(
        message_group,
        text="MessageBox",
        variable=message_display_var,
        value="box",
    ).place(x=16, y=4)
    tk.Radiobutton(
        message_group,
        text="Console",
        variable=message_display_var,
        value="console",
    ).place(x=120, y=4)

    password_prompt_group = tk.LabelFrame(root, text="Ask for password via")
    password_prompt_group.place(x=268, y=238, width=240, height=56)
    tk.Radiobutton(
        password_prompt_group,
        text="Window",
        variable=password_prompt_var,
        value="box",
    ).place(x=16, y=4)
    tk.Radiobutton(
        password_prompt_group,
        text="Console",
        variable=password_prompt_var,
        value="console",
    ).place(x=120, y=4)

    tk.Label(root, text="Password (leave blank for no password):").place(x=padding, y=306)
    tk.Entry(root, textvariable=password_var, show="*", width=58).place(x=padding, y=326)

    version_label = tk.Label(root, text=VERSION)
    version_label.place(x=padding, y=352)

    credit_label = tk.Label(
        root,
        text=PROJECT_URL,
        fg="blue",
        cursor="hand2",
    )
    credit_label.place(x=padding + 56, y=352)
    credit_label.bind(
        "<Button-1>",
        lambda _event: subprocess.run(["explorer", PROJECT_URL], check=False),
    )

    tk.Button(root, text="Encrypt", width=12, command=on_encrypt).place(x=304, y=390)
    tk.Button(root, text="Cancel", width=12, command=on_cancel).place(x=408, y=390)

    root.protocol("WM_DELETE_WINDOW", on_cancel)
    root.mainloop()


def main() -> None:
    show_encryption_form()


if __name__ == "__main__":
    main()
