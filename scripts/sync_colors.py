import os
import re
import json

def parse_design_tokens(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # regex to find static const Color name = Color(0xFFXXXXXX);
    color_pattern = re.compile(r'static\s+const\s+Color\s+(\w+)\s*=\s*Color\(0xFF([0-9A-Fa-f]{6})\);')
    matches = color_pattern.findall(content)
    
    colors = {}
    for name, hex_val in matches:
        colors[name] = hex_val.upper()
    return colors

def update_android_colors(colors, values_path, is_night):
    # Mapping our design tokens to values in colors.xml
    # For Light:
    #   widget_background = lightBackground
    #   widget_surface = lightSurface
    #   widget_surface_secondary = lightSurfaceSecondary
    #   widget_text_primary = lightTextPrimary
    #   widget_text_secondary = lightTextSecondary
    #   widget_divider = lightDivider
    #   widget_accent = accent
    #   widget_error = error
    
    # For Night:
    #   widget_background = darkBackground
    #   widget_surface = darkSurface
    #   widget_surface_secondary = darkSurfaceSecondary
    #   widget_text_primary = darkTextPrimary
    #   widget_text_secondary = darkTextSecondary
    #   widget_divider = darkDivider
    #   widget_accent = accent
    #   widget_error = error
    
    prefix = "dark" if is_night else "light"
    mapped_colors = {
        "widget_background": colors[f"{prefix}Background"],
        "widget_surface": colors[f"{prefix}Surface"] if f"{prefix}Surface" in colors else colors["darkSurface"], # fallback
        "widget_surface_secondary": colors[f"{prefix}SurfaceSecondary"],
        "widget_text_primary": colors[f"{prefix}TextPrimary"],
        "widget_text_secondary": colors[f"{prefix}TextSecondary"],
        "widget_divider": colors[f"{prefix}Divider"],
        "widget_accent": colors["accent"],
        "widget_error": colors["error"],
    }
    
    # Read existing XML file
    with open(values_path, 'r') as f:
        xml_content = f.read()
        
    for key, hex_val in mapped_colors.items():
        # replace <color name="key">#XXXXXX</color>
        pattern = re.compile(rf'<color name="{key}">#[0-9A-Fa-f]{{6}}</color>')
        xml_content = pattern.sub(f'<color name="{key}">#{hex_val}</color>', xml_content)
        
    with open(values_path, 'w') as f:
        f.write(xml_content)
    print(f"Updated Android {values_path}")

def update_ios_color_sets(colors, assets_path):
    # Mapping for iOS: we will update Contents.json of each colorset
    # The colorsets contain appearances: light (default) and dark (appearance luminosity dark)
    # The name of colorsets are:
    # WidgetAccent, WidgetBackground, WidgetDivider, WidgetSurface, WidgetSurfaceSecondary, WidgetTextPrimary, WidgetTextSecondary
    
    mappings = {
        "WidgetAccent": ("accent", "accent"),
        "WidgetBackground": ("lightBackground", "darkBackground"),
        "WidgetDivider": ("lightDivider", "darkDivider"),
        "WidgetSurface": ("lightSurface", "darkSurface"),
        "WidgetSurfaceSecondary": ("lightSurfaceSecondary", "darkSurfaceSecondary"),
        "WidgetTextPrimary": ("lightTextPrimary", "darkTextPrimary"),
        "WidgetTextSecondary": ("lightTextSecondary", "darkTextSecondary"),
    }
    
    for colorset_name, (light_key, dark_key) in mappings.items():
        colorset_dir = os.path.join(assets_path, f"{colorset_name}.colorset")
        if not os.path.exists(colorset_dir):
            os.makedirs(colorset_dir)
            
        contents_path = os.path.join(colorset_dir, "Contents.json")
        
        light_hex = colors[light_key]
        dark_hex = colors[dark_key]
        
        def hex_to_components(hex_str):
            r = hex_str[0:2]
            g = hex_str[2:4]
            b = hex_str[4:6]
            return f"0x{r}", f"0x{g}", f"0x{b}"
            
        lr, lg, lb = hex_to_components(light_hex)
        dr, dg, db = hex_to_components(dark_hex)
        
        json_data = {
          "info": {
            "author": "xcode",
            "version": 1
          },
          "colors": [
            {
              "idiom": "universal",
              "color": {
                "color-space": "srgb",
                "components": {
                  "red": lr,
                  "green": lg,
                  "blue": lb,
                  "alpha": "1.000"
                }
              }
            },
            {
              "idiom": "universal",
              "appearances": [
                {
                  "appearance": "luminosity",
                  "value": "dark"
                }
              ],
              "color": {
                "color-space": "srgb",
                "components": {
                  "red": dr,
                  "green": dg,
                  "blue": db,
                  "alpha": "1.000"
                }
              }
            }
          ]
        }
        
        with open(contents_path, 'w') as f:
            json.dump(json_data, f, indent=2)
            
        print(f"Updated iOS color set {colorset_name}")

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tokens_path = os.path.join(base_dir, "flutter_client", "lib", "theme", "design_tokens.dart")
    android_light = os.path.join(base_dir, "flutter_client", "android", "app", "src", "main", "res", "values", "colors.xml")
    android_dark = os.path.join(base_dir, "flutter_client", "android", "app", "src", "main", "res", "values-night", "colors.xml")
    ios_assets = os.path.join(base_dir, "flutter_client", "ios", "Runner", "Assets.xcassets")
    
    colors = parse_design_tokens(tokens_path)
    
    if os.path.exists(android_light):
        update_android_colors(colors, android_light, is_night=False)
    if os.path.exists(android_dark):
        update_android_colors(colors, android_dark, is_night=True)
    if os.path.exists(ios_assets):
        update_ios_color_sets(colors, ios_assets)

if __name__ == "__main__":
    main()
