#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GIMP Layer Exporter - Single File Version
Exports all layers from a GIMP file to individual PNG files
Can be run directly from command line without separate scripts
"""

import sys
import os
import subprocess
import json
import re
import platform
import argparse
from pathlib import Path
import gi

# Try to import GIMP modules, but don't fail if we're not in GIMP context yet
try:
    gi.require_version('Gimp', '3.0')
    from gi.repository import Gimp, Gio
except ImportError:
    pass  # We'll handle this later when needed

def sanitize_filename(name):
    """Remove invalid characters from filenames"""
    sanitized = re.sub(r'[<>:"/\\|?*]', '', name)
    sanitized = sanitized.replace(' ', '_')
    sanitized = sanitized.replace('#', '_')
    sanitized = sanitized.replace('&', '_')
    sanitized = sanitized.replace('@', '_')
    return sanitized.lower()

def find_gimp_executable():
    """Automatically find the GIMP executable based on the operating system"""
    system = platform.system().lower()
    
    if system == "windows":
        # Common Windows installation paths
        possible_paths = [
            r"C:\Program Files\GIMP 3\bin\gimp-3.0.exe",
            r"C:\Program Files\GIMP 3\bin\gimp-console-3.0.exe",
            r"C:\Program Files\GIMP\bin\gimp-3.0.exe",
            r"C:\Program Files\GIMP\bin\gimp-console-3.0.exe",
            os.path.expanduser(r"~\AppData\Local\Programs\GIMP 3\bin\gimp-3.0.exe"),
            os.path.expanduser(r"~\AppData\Local\Programs\GIMP 3\bin\gimp-console-3.0.exe")
        ]
        
        # Check PATH environment variable
        path_env = os.environ.get("PATH", "")
        for path_dir in path_env.split(os.pathsep):
            gimp_path = os.path.join(path_dir, "gimp-3.0.exe")
            if os.path.exists(gimp_path):
                return gimp_path
            gimp_console_path = os.path.join(path_dir, "gimp-console-3.0.exe")
            if os.path.exists(gimp_console_path):
                return gimp_console_path
    
    elif system == "darwin":  # macOS
        possible_paths = [
            "/Applications/GIMP.app/Contents/MacOS/gimp",
            "/Applications/GIMP-3.0.app/Contents/MacOS/gimp",
            os.path.expanduser("~/Applications/GIMP.app/Contents/MacOS/gimp"),
            "/opt/homebrew/bin/gimp",
            "/usr/local/bin/gimp"
        ]
    
    else:  # Linux and other Unix-like systems
        possible_paths = [
            "/usr/bin/gimp",
            "/usr/local/bin/gimp",
            "/snap/bin/gimp",
            os.path.expanduser("~/.local/bin/gimp"),
            "/app/bin/gimp"  # For Flatpak installations
        ]
    
    # Check all possible paths
    for path in possible_paths:
        if os.path.exists(path) and os.access(path, os.X_OK):
            return path
    
    # Fallback to just "gimp" which will use PATH
    return "gimp"

def export_layer_in_gimp(layer, output_dir, prefix="", group_path=""):
    """Export a single layer as PNG (GIMP context only)"""
    if not layer.get_visible():
        return False
    
    # Create directory for this group
    layer_dir = Path(output_dir) / group_path
    layer_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate filename
    layer_name = sanitize_filename(layer.get_name())
    filename = f"{prefix}{layer_name}.png"
    full_path = layer_dir / filename
    
    try:
        # Create temporary image with just this layer
        temp_image = Gimp.Image.new(layer.get_width(), layer.get_height(), Gimp.ImageBaseType.RGB)
        
        # Copy layer to temp image
        layer_copy = layer.duplicate()
        temp_image.insert_layer(layer_copy, None, 0)
        
        # Merge visible layers (just our one layer)
        merged_layer = temp_image.merge_visible_layers(Gimp.MergeType.CLIP_TO_IMAGE)
        
        # Export as PNG
        output_file = Gio.File.new_for_path(str(full_path))
        config = Gimp.get_export_procedure("png").create_config()
        config.set_property("compression", 9)
        config.set_property("save-transparent", True)
        
        result = Gimp.get_pdb().run_procedure(
            "file-png-save",
            [
                temp_image,
                merged_layer,
                output_file,
                output_file,
                config
            ]
        )
        
        temp_image.delete()
        
        return result.status == Gimp.PDBStatusType.SUCCESS
            
    except Exception as e:
        print(f"❌ Error exporting {layer.get_name()}: {str(e)}")
        return False

def export_group_in_gimp(group, output_dir, prefix="", group_path=""):
    """Recursively export all layers in a group (GIMP context only)"""
    if not hasattr(group, "is_group_layer") or not group.is_group_layer():
        return
    
    group_name = sanitize_filename(group.get_name())
    current_path = f"{group_path}/{group_name}" if group_path else group_name
    
    try:
        # Get children layers
        children = group.get_children() if hasattr(group, "get_children") else []
        
        for layer in children:
            if hasattr(layer, "is_group_layer") and layer.is_group_layer():
                export_group_in_gimp(layer, output_dir, prefix, current_path)
            else:
                export_layer_in_gimp(layer, output_dir, prefix, current_path)
                
    except Exception as e:
        print(f"⚠️ Error processing group {group.get_name()}: {str(e)}")

def export_layers_in_gimp(image, output_dir, prefix=""):
    """Export all layers from an image (GIMP context only)"""
    # Export root layers
    root_layers = image.get_layers() if hasattr(image, "get_layers") else []
    for layer in root_layers:
        if hasattr(layer, "is_group_layer") and layer.is_group_layer():
            export_group_in_gimp(layer, output_dir, prefix)
        else:
            export_layer_in_gimp(layer, output_dir, prefix)

def gimp_main(input_file, output_dir, prefix="", psx_optimize=True, debug=False):
    """Main function that runs inside GIMP"""
    try:
        # Load the image
        file = Gio.File.new_for_path(input_file)
        image = Gimp.Image.new_from_file(file, None)
        
        if not image:
            raise RuntimeError(f"Failed to load image: {input_file}")
        
        if debug:
            print(f"✅ Image loaded successfully: {image.get_name()}")
            print(f"📏 Dimensions: {image.get_width()}x{image.get_height()}")
        
        # Export layers
        export_layers_in_gimp(image, output_dir, prefix)
        
        # Clean up
        image.delete()
        
        if debug:
            print("🧹 Memory cleaned up")
        
        return True
        
    except Exception as e:
        print(f"❌ Fatal error in GIMP script: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

def run_gimp_export(input_file, output_dir, prefix="", psx_optimize=True, debug=False):
    """Run the export process through GIMP in batch mode"""
    print("="*60)
    print("GIMP BATCH LAYER EXPORTER")
    print("="*60)
    print(f"Input file: {input_file}")
    print(f"Output directory: {output_dir}")
    print(f"Prefix: {prefix}")
    print(f"PSX Optimization: {'Enabled' if psx_optimize else 'Disabled'}")
    print(f"Debug mode: {'Enabled' if debug else 'Disabled'}")
    print("="*60 + "\n")
    
    # Find GIMP executable
    gimp_path = find_gimp_executable()
    print(f"🔍 Found GIMP at: {gimp_path}")
    
    # Get absolute paths
    input_file_abs = os.path.abspath(input_file)
    output_dir_abs = os.path.abspath(output_dir)
    
    # Create output directory if it doesn't exist
    Path(output_dir_abs).mkdir(parents=True, exist_ok=True)
    
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Create the Python code to execute within GIMP
    python_code = f"""
import sys
import os
import gi
gi.require_version('Gimp', '3.0')
from gi.repository import Gimp, Gio
import json
import re
from pathlib import Path

def sanitize_filename(name):
    sanitized = re.sub(r'[<>:"/\\\\|?*]', '', name)
    sanitized = sanitized.replace(' ', '_')
    sanitized = sanitized.replace('#', '_')
    sanitized = sanitized.replace('&', '_')
    sanitized = sanitized.replace('@', '_')
    return sanitized.lower()

def export_layer_in_gimp(layer, output_dir, prefix="", group_path=""):
    if not layer.get_visible():
        return False
    
    layer_dir = Path(output_dir) / group_path
    layer_dir.mkdir(parents=True, exist_ok=True)
    
    layer_name = sanitize_filename(layer.get_name())
    filename = f"{{prefix}}{{layer_name}}.png"
    full_path = layer_dir / filename
    
    try:
        temp_image = Gimp.Image.new(layer.get_width(), layer.get_height(), Gimp.ImageBaseType.RGB)
        layer_copy = layer.duplicate()
        temp_image.insert_layer(layer_copy, None, 0)
        merged_layer = temp_image.merge_visible_layers(Gimp.MergeType.CLIP_TO_IMAGE)
        
        output_file = Gio.File.new_for_path(str(full_path))
        config = Gimp.get_export_procedure("png").create_config()
        config.set_property("compression", 9)
        config.set_property("save-transparent", True)
        
        result = Gimp.get_pdb().run_procedure(
            "file-png-save",
            [
                temp_image,
                merged_layer,
                output_file,
                output_file,
                config
            ]
        )
        
        temp_image.delete()
        return result.status == Gimp.PDBStatusType.SUCCESS
            
    except Exception as e:
        print(f"❌ Error exporting {{layer.get_name()}}: {{str(e)}}")
        return False

def export_group_in_gimp(group, output_dir, prefix="", group_path=""):
    if not hasattr(group, "is_group_layer") or not group.is_group_layer():
        return
    
    group_name = sanitize_filename(group.get_name())
    current_path = f"{{group_path}}/{{group_name}}" if group_path else group_name
    
    try:
        children = group.get_children() if hasattr(group, "get_children") else []
        for layer in children:
            if hasattr(layer, "is_group_layer") and layer.is_group_layer():
                export_group_in_gimp(layer, output_dir, prefix, current_path)
            else:
                export_layer_in_gimp(layer, output_dir, prefix, current_path)
    except Exception as e:
        print(f"⚠️ Error processing group {{group.get_name()}}: {{str(e)}}")

def export_layers_in_gimp(image, output_dir, prefix=""):
    root_layers = image.get_layers() if hasattr(image, "get_layers") else []
    for layer in root_layers:
        if hasattr(layer, "is_group_layer") and layer.is_group_layer():
            export_group_in_gimp(layer, output_dir, prefix)
        else:
            export_layer_in_gimp(layer, output_dir, prefix)

def main():
    input_file = "{input_file_abs}"
    output_dir = "{output_dir_abs}"
    prefix = "{prefix}"
    psx_optimize = {"true" if psx_optimize else "false"}
    debug = {"true" if debug else "false"}
    
    try:
        print(f"📥 Loading image: {{input_file}}")
        file = Gio.File.new_for_path(input_file)
        image = Gimp.Image.new_from_file(file, None)
        
        if not image:
            raise RuntimeError(f"Failed to load image: {{input_file}}")
        
        if debug:
            print(f"✅ Image loaded successfully: {{image.get_name()}}")
            print(f"📏 Dimensions: {{image.get_width()}}x{{image.get_height()}}")
        
        print("🎨 Exporting layers...")
        export_layers_in_gimp(image, output_dir, prefix)
        
        image.delete()
        
        if debug:
            print("🧹 Memory cleaned up")
        
        print("✅ Layer export completed successfully!")
        return 0
        
    except Exception as e:
        print(f"❌ Fatal error: {{str(e)}}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
    """
    
    # Prepare command line arguments
    cmd_args = [
        gimp_path,
        "-d",  # Disable user interface
        "-f",  # Disable splash screen
        "--batch-interpreter", "python-fu-eval",
        "-b", python_code.strip(),
        "-b", "pdb.gimp_quit(1)"  # Exit GIMP when done
    ]
    
    # For debugging, show the UI
    if debug:
        cmd_args.remove("-d")
        cmd_args.remove("-f")
    
    print("🚀 Starting GIMP in batch mode...")
    
    try:
        # Run the command
        result = subprocess.run(
            cmd_args,
            capture_output=True,
            text=True,
            env=os.environ.copy()
        )
        
        # Print output
        if result.stdout:
            print("📋 GIMP Output:")
            print(result.stdout)
        
        if result.stderr:
            print("⚠️  GIMP Errors/Warnings:")
            print(result.stderr)
        
        # Check if successful
        if result.returncode == 0:
            print("✅ GIMP script executed successfully!")
            return True
        else:
            print(f"❌ GIMP script failed with return code: {result.returncode}")
            return False
            
    except FileNotFoundError:
        print(f"❌ GIMP executable not found at: {gimp_path}")
        print("Please make sure GIMP is installed or specify the path manually")
        return False
    except Exception as e:
        print(f"❌ Error running GIMP: {str(e)}")
        return False

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Export GIMP layers as individual PNG files')
    
    parser.add_argument('--input', required=True, help='Input .xcf file to process')
    parser.add_argument('--output-dir', required=True, help='Output directory for exported layers')
    parser.add_argument('--prefix', default='', help='Prefix for exported file names')
    parser.add_argument('--no-psx-optimize', action='store_true', help='Disable PSX optimization')
    parser.add_argument('--debug', action='store_true', help='Show GIMP UI for debugging')
    
    return parser.parse_args()

def main():
    """Main function"""
    args = parse_arguments()
    
    success = run_gimp_export(
        input_file=args.input,
        output_dir=args.output_dir,
        prefix=args.prefix,
        psx_optimize=not args.no_psx_optimize,
        debug=args.debug
    )
    
    if success:
        print("\n🎉 SUCCESS! All layers have been exported successfully.")
        print(f"📁 Check the output directory: {os.path.abspath(args.output_dir)}")
        sys.exit(0)
    else:
        print("\n❌ FAILED! There was an error during the export process.")
        sys.exit(1)

if __name__ == "__main__":
    main()
