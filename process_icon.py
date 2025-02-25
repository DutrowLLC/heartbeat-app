from PIL import Image
import os

def create_icon_sizes(input_path, output_dir):
    # Dictionary of required sizes (size: filename)
    icon_sizes = {
        (20, 2): "AppIcon-20@2x.png",  # 40x40
        (20, 3): "AppIcon-20@3x.png",  # 60x60
        (29, 2): "AppIcon-29@2x.png",  # 58x58
        (29, 3): "AppIcon-29@3x.png",  # 87x87
        (40, 2): "AppIcon-40@2x.png",  # 80x80
        (40, 3): "AppIcon-40@3x.png",  # 120x120
        (60, 2): "AppIcon-60@2x.png",  # 120x120
        (60, 3): "AppIcon-60@3x.png",  # 180x180
        (76, 1): "AppIcon-76.png",     # 76x76
        (76, 2): "AppIcon-76@2x.png",  # 152x152
        (83.5, 2): "AppIcon-83.5@2x.png",  # 167x167
        (1024, 1): "AppIcon-1024.png"  # 1024x1024
    }
    
    # Open the source image
    img = Image.open(input_path)
    
    # Create each size
    for (base_size, scale), filename in icon_sizes.items():
        size = int(base_size * scale)
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        output_path = os.path.join(output_dir, filename)
        resized.save(output_path, 'PNG')
        print(f"Created {filename} ({size}x{size})")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_path = os.path.join(script_dir, "AppIcon.png")
    output_dir = os.path.join(script_dir, "Assets.xcassets/AppIcon.appiconset")
    
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    create_icon_sizes(input_path, output_dir)
