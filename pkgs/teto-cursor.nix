{
  lib,
  fetchzip,
  stdenvNoCC,
  win2xcur,
}:

let
  version = "1";
  src = fetchzip {
    name = "teto-cursor";
    url = "https://s3.s4r.in/teto-cursor.zip";
    hash = "sha256-un5FsVtjWORScQRlj8rrhYdtUjR3o7UzliXfN5ML8rw=";
    stripRoot = false;
  };
in
stdenvNoCC.mkDerivation {
  pname = "teto-cursor";
  inherit version src;

  nativeBuildInputs = [ win2xcur ];

  buildPhase = ''
    cd "teto 1"
    mkdir output
    win2xcur -o output *.ani *.cur
    win2xcur -o output --scale 2 *.ani *.cur
    win2xcur -o output --scale 3 *.ani *.cur
  '';

  installPhase = ''
    local cursors=$out/share/icons/teto-cursor/cursors
    mkdir -p $cursors
    cp -r output/. $cursors/

    symlink() { ln -sf "$1" "$cursors/$2"; }

    # normal → default arrow
    symlink normal default
    symlink normal arrow
    symlink normal top_left_arrow
    symlink normal left_ptr

    # busy → wait/watch
    symlink busy wait
    symlink busy watch

    # background → working-in-background
    symlink background progress
    symlink background "left_ptr_watch"
    symlink background "08e8e1c95fe2fc01f976f1e063a24ccd"
    symlink background "3ecb610c1bf2410f44200f48c40d3599"
    symlink background "00000000000000020006000e7e9ffc3f"

    # help → question
    symlink help question_arrow
    symlink help left_ptr_help
    symlink help whats_this
    symlink help "d9ce0ab605698f320427677b458ad60b"
    symlink help "5c6cd98b3f3ebcb1f9c7f1c204630408"
    symlink help dnd-ask

    # link → hand/pointer
    symlink link hand2
    symlink link pointer
    symlink link pointing_hand
    symlink link alias
    symlink link dnd-link
    symlink link "9d800788f1b08800ae810202380a0822"
    symlink link "e29285e634086352946a0e7090d73106"
    symlink link "640fb0e74195791501fd1ed57b41487f"
    symlink link "3085a0e285430894940527032f8b26df"
    symlink link "a2a266d0498c3104214a47bd64ab0fc8"

    # text → ibeam
    symlink text xterm
    symlink text ibeam

    # precision → crosshair
    symlink precision crosshair
    symlink precision cross
    symlink precision tcross
    symlink precision diamond_cross

    # unavailable → no
    symlink unavailable crossed_circle
    symlink unavailable forbidden
    symlink unavailable not-allowed
    symlink unavailable circle
    symlink unavailable no-drop
    symlink unavailable dnd-none
    symlink unavailable "03b6e0fcb3499374a867c041f52298f0"

    # move → fleur/all-scroll
    symlink move fleur
    symlink move all-scroll
    symlink move size_all
    symlink move grabbing
    symlink move closedhand
    symlink move pointer_move
    symlink move dnd-move
    symlink move "4498f0e0c1937ffe01fd06f973665830"
    symlink move "9081237383d90e509aa00f00170e968f"
    symlink move "fcf21c00b30f7e3f83fe0dfd12e71cff"

    # horizontal ↔ resize
    symlink horizontal sb_h_double_arrow
    symlink horizontal h_double_arrow
    symlink horizontal ew-resize
    symlink horizontal col-resize
    symlink horizontal size-hor
    symlink horizontal size_hor
    symlink horizontal split_h
    symlink horizontal e-resize
    symlink horizontal w-resize
    symlink horizontal "028006030e0e7ebffc7f7070c0600140"
    symlink horizontal "14fef782d02440884392942c1120523"

    # vertical ↕ resize
    symlink vertical sb_v_double_arrow
    symlink vertical v_double_arrow
    symlink vertical double_arrow
    symlink vertical ns-resize
    symlink vertical row-resize
    symlink vertical size-ver
    symlink vertical size_ver
    symlink vertical split_v
    symlink vertical n-resize
    symlink vertical s-resize
    symlink vertical bottom_side
    symlink vertical top_side
    symlink vertical "00008160000006810000408080010102"
    symlink vertical "2870a09082c103050810ffdffffe0204"

    # diagonal 1 ╲ NW-SE
    symlink "diagonal 1" bottom_right_corner
    symlink "diagonal 1" top_left_corner
    symlink "diagonal 1" nwse-resize
    symlink "diagonal 1" size_fdiag
    symlink "diagonal 1" bd_double_arrow
    symlink "diagonal 1" "c7088f0f3e6c8088236ef8e1e3e70000"

    # diagonal 2 ╱ NE-SW
    symlink "diagonal 2" bottom_left_corner
    symlink "diagonal 2" top_right_corner
    symlink "diagonal 2" nesw-resize
    symlink "diagonal 2" size_bdiag
    symlink "diagonal 2" fd_double_arrow
    symlink "diagonal 2" "fcf1c3c7cd4491d801f1e1c78f100000"

    # pen
    symlink pen pencil

    # copy/dnd
    symlink normal copy
    symlink normal dnd-copy
    symlink normal "1081e37283d90000800003c07f3ef6bf"
    symlink normal "6407b0e94181790501fd1ed57b41487f"
    symlink normal "b66166c04f8c3109214a4fbd64a50fc8"

    cat > $out/share/icons/teto-cursor/cursor.theme <<'EOF'
[Icon Theme]
Name=teto-cursor
EOF
    cat > $out/share/icons/teto-cursor/index.theme <<'EOF'
[Icon Theme]
Name=teto-cursor
Comment=Teto cursor theme
EOF
  '';
}
