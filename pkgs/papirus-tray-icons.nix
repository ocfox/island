{
  lib,
  runCommand,
  papirus-icon-theme,
  python3,
}:
lib.hiPrio (
  runCommand "papirus-tray-icons"
    {
      nativeBuildInputs = [ python3 ];
      passthru = {
        inherit papirus-icon-theme;
      };
    }
    ''
      python3 - <<'EOF'
      import os

      papirus_store = "${papirus-icon-theme}/share/icons"
      out = os.environ["out"]

      def make_scaled_svg(orig_svg, scale=1.25):
          if 'transform="matrix(1,0,0,1,4,4)"' in orig_svg:
              return orig_svg.replace('transform="matrix(1,0,0,1,4,4)"', f'transform="matrix({scale},0,0,{scale},2,2)"')
          if "</defs>" in orig_svg:
              idx = orig_svg.index("</defs>") + len("</defs>")
          elif "<svg" in orig_svg:
              idx = orig_svg.index(">", orig_svg.index("<svg")) + 1
          else:
              return orig_svg
          pre = orig_svg[:idx]
          post = orig_svg[idx:orig_svg.rindex("</svg>")]
          return f'{pre}\n <g transform="translate(12, 12) scale({scale}) translate(-12, -12)">\n{post}\n </g>\n</svg>'

      en_template = """<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 24 24" version="1.1">
       <defs>
        <style id="current-color-scheme" type="text/css">
         .ColorScheme-Text {{ color:{color}; }}
        </style>
       </defs>
       <g transform="translate(12, 12) scale(1.25) translate(-12, -12)">
        <path style="fill:currentColor" class="ColorScheme-Text" fill-rule="evenodd" d="
          M 6 4 C 4.892 4 4 4.892 4 6
          L 4 18 C 4 19.108 4.892 20 6 20
          L 18 20 C 19.108 20 20 19.108 20 18
          L 20 6 C 20 4.892 19.108 4 18 4 Z
          M 6.5 7 L 11 7 L 11 8.6 L 8.5 8.6 L 8.5 11 L 10.7 11 L 10.7 12.6 L 8.5 12.6 L 8.5 15.4 L 11 15.4 L 11 17 L 6.5 17 Z
          M 12.5 7 L 14.5 7 L 16.3 13.8 L 16.3 7 L 18 7 L 18 17 L 16 17 L 14.2 10.2 L 14.2 17 L 12.5 17 Z
        "/>
       </g>
      </svg>"""

      configs = [
          ("Papirus-Dark", f"{papirus_store}/Papirus", "#dfdfdf"),
          ("Papirus-Light", f"{papirus_store}/Papirus-Light", "#444444")
      ]

      sizes = [
          "16x16", "22x22", "24x24", "32x32", "48x48",
          "16x16@2x", "22x22@2x", "24x24@2x", "32x32@2x", "48x48@2x"
      ]

      for theme_name, theme_src, def_color in configs:
          theme_dest = f"{out}/share/icons/{theme_name}"
          
          with open(f"{theme_src}/24x24/panel/steam_tray_mono.svg") as f:
              steam_base = make_scaled_svg(f.read(), 1.25)
          with open(f"{theme_src}/24x24/panel/fcitx-shuangpin-panel.svg") as f:
              sp_base = make_scaled_svg(f.read(), 1.25)
          with open(f"{theme_src}/24x24/panel/fcitx-mozc-direct.svg") as f:
              mozc_d_base = make_scaled_svg(f.read(), 1.25)
          with open(f"{theme_src}/24x24/panel/fcitx-mozc-hiragana.svg") as f:
              mozc_h_base = make_scaled_svg(f.read(), 1.25)
              
          for s in sizes:
              base_s = s.replace("@2x", "")
              w, h = map(int, base_s.split("x"))
              if "@2x" in s:
                  w *= 2
                  h *= 2
                  
              panel_dir = f"{theme_dest}/{s}/panel"
              sym_dir = f"{theme_dest}/{s}/symbolic/devices"
              actions_dir = f"{theme_dest}/{s}/actions"
              status_dir = f"{theme_dest}/{s}/status"
              
              for d in [panel_dir, sym_dir, actions_dir, status_dir]:
                  os.makedirs(d, exist_ok=True)
                  
              # EN
              en_content = en_template.format(width=w, height=h, color=def_color)
              for d in [panel_dir, sym_dir]:
                  for fname in ["input-keyboard.svg", "input-keyboard-symbolic.svg"]:
                      with open(f"{d}/{fname}", "w") as f:
                          f.write(en_content)
                          
              # Steam
              with open(f"{panel_dir}/steam_tray_mono.svg", "w") as f:
                  f.write(steam_base.replace('width="24" height="24"', f'width="{w}" height="{h}" viewBox="0 0 24 24"'))
                  
              # Shuangpin
              sp_content = sp_base.replace('width="24" height="24"', f'width="{w}" height="{h}" viewBox="0 0 24 24"')
              for d in [panel_dir, actions_dir, status_dir]:
                  for fname in [
                      "fcitx-shuangpin.svg",
                      "fcitx-shuangpin-panel.svg",
                      "fcitx-shuangpin-symbolic.svg",
                      "fcitx-shuangpin-libpinyin.svg",
                      "fcitx-shuangpin-libpinyin-panel.svg",
                      "fcitx_shuangpin.svg",
                      "org.fcitx.Fcitx5.fcitx-shuangpin.svg"
                  ]:
                      with open(f"{d}/{fname}", "w") as f:
                          f.write(sp_content)
                          
              # Mozc
              mozc_map = {
                  "fcitx-mozc-direct.svg": mozc_d_base,
                  "fcitx_mozc_direct.svg": mozc_d_base,
                  "fcitx-mozc-hiragana.svg": mozc_h_base,
                  "fcitx_mozc_hiragana.svg": mozc_h_base,
              }
              for d in [panel_dir, actions_dir, status_dir]:
                  for fname, content in mozc_map.items():
                      with open(f"{d}/{fname}", "w") as f:
                          f.write(content.replace('width="24" height="24"', f'width="{w}" height="{h}" viewBox="0 0 24 24"'))
      EOF
    ''
)
