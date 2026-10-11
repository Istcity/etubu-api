import ftplib
import os

FTP_HOST = "ftp.etubu.com"
FTP_USER = "httpdset"
FTP_PASS = "+6ViRcb1Qs?f"

files_to_upload = [
    ("public/app.html", "public_html/app.html"),
    ("public/index-app.html", "public_html/index-app.html"),
    ("public/css/cockpit-magic.css", "public_html/css/cockpit-magic.css"),
    ("public/js/app.js", "public_html/js/app.js"),
    ("public/js/scene.js", "public_html/js/scene.js"),
    ("public/js/i18n.js", "public_html/js/i18n.js"),
    ("public/js/intro.js", "public_html/js/intro.js"),
    ("public/index.html", "public_html/index.html"),
    ("public/css/motion-storefront.css", "public_html/css/motion-storefront.css"),
    ("public/css/style.css", "public_html/css/style.css"),
    ("public/.htaccess", "public_html/.htaccess"),
]

print(f"Connecting to {FTP_HOST} as {FTP_USER}...")
ftp = ftplib.FTP()
ftp.connect(FTP_HOST, 21, timeout=30)
ftp.login(FTP_USER, FTP_PASS)
print("Connected successfully!")

for local_path, remote_path in files_to_upload:
    if not os.path.exists(local_path):
        print(f"Skipping {local_path} (not found)")
        continue
    
    # Ensure remote directory exists
    remote_dir = os.path.dirname(remote_path)
    try:
        ftp.cwd("/")
        for part in remote_dir.split("/"):
            if not part:
                continue
            try:
                ftp.cwd(part)
            except ftplib.error_perm:
                ftp.mkd(part)
                ftp.cwd(part)
    except Exception as e:
        print(f"Dir check error: {e}")

    remote_filename = os.path.basename(remote_path)
    print(f"Uploading {local_path} -> {remote_path}...")
    with open(local_path, "rb") as f:
        ftp.storbinary(f"STOR {remote_filename}", f)
    print(f"Uploaded {remote_path} ({os.path.getsize(local_path)} bytes)")

ftp.quit()
print("All files deployed to Cenuta cPanel successfully!")
