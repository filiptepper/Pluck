import os
import sys
import json
import subprocess

# Resolve absolute paths dynamically relative to this script's location
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(script_dir)

# 1. Use Pluck/AppIcon_Source.jpg (absolute path) as the default source image path.
# 2. Accept a custom source image path via command-line arguments (sys.argv[1]).
source_image = os.path.join(project_root, "Pluck", "AppIcon_Source.jpg")
if len(sys.argv) > 1:
    source_image = os.path.abspath(sys.argv[1])

# 3. Check if the source image file exists, printing a helpful error message and exiting with code 1 if it is missing.
if not os.path.exists(source_image):
    print(f"Error: Source image file '{source_image}' not found.", file=sys.stderr)
    print("Please make sure the source artwork exists in the repository or specify a custom path as an argument.", file=sys.stderr)
    sys.exit(1)

assets_dir = os.path.join(project_root, "Pluck", "Assets.xcassets")
target_dir = os.path.join(assets_dir, "AppIcon.appiconset")

# Create parent directories
os.makedirs(target_dir, exist_ok=True)

# 4. Create a root Contents.json file inside Pluck/Assets.xcassets/Contents.json
root_contents = {
    "info": {
        "version": 1,
        "author": "xcode"
    }
}
root_contents_path = os.path.join(assets_dir, "Contents.json")
try:
    with open(root_contents_path, "w") as f:
        json.dump(root_contents, f, indent=2)
except IOError as e:
    print(f"Error writing root Contents.json: {e}", file=sys.stderr)
    sys.exit(1)

sizes = [
    {"size": 16, "scale": 1, "filename": "icon_16x16.png"},
    {"size": 16, "scale": 2, "filename": "icon_16x16@2x.png"},
    {"size": 32, "scale": 1, "filename": "icon_32x32.png"},
    {"size": 32, "scale": 2, "filename": "icon_32x32@2x.png"},
    {"size": 128, "scale": 1, "filename": "icon_128x128.png"},
    {"size": 128, "scale": 2, "filename": "icon_128x128@2x.png"},
    {"size": 256, "scale": 1, "filename": "icon_256x256.png"},
    {"size": 256, "scale": 2, "filename": "icon_256x256@2x.png"},
    {"size": 512, "scale": 1, "filename": "icon_512x512.png"},
    {"size": 512, "scale": 2, "filename": "icon_512x512@2x.png"},
]

contents = {
    "images": [],
    "info": {
        "version": 1,
        "author": "xcode"
    }
}

for item in sizes:
    contents["images"].append({
        "size": f"{item['size']}x{item['size']}",
        "idiom": "mac",
        "filename": item["filename"],
        "scale": f"{item['scale']}x"
    })

try:
    with open(os.path.join(target_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
except IOError as e:
    print(f"Error writing AppIcon Contents.json: {e}", file=sys.stderr)
    sys.exit(1)

# Gated check: If sys.platform != "darwin", print the warning message and exit cleanly after writing the Contents.json files.
if sys.platform != "darwin":
    print("Warning: macOS-exclusive 'sips' utility is not available on this platform.")
    print("Skipping icon image generation, but asset catalog structure has been prepared.")
    sys.exit(0)

# Run sips on macOS to generate image files
for item in sizes:
    px_size = item["size"] * item["scale"]
    out_path = os.path.join(target_dir, item["filename"])
    cmd = ["sips", "-s", "format", "png", "-z", str(px_size), str(px_size), source_image, "--out", out_path]
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: failed to run sips command: {e}", file=sys.stderr)
        sys.exit(1)

print("Icons generated successfully.")
