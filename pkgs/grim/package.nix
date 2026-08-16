{ grim }:

grim.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    # Keep the 10 bits per channel that a capture of a 10-bit output provides
    ./10bpc-png.patch
    # Convert captures of HDR outputs to SDR, so they are not written as
    # PQ-encoded BT.2020 samples that every viewer reads as plain sRGB
    ./hdr-tonemap.patch
  ];
})

