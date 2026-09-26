use crate::model::error::MilkError;
use crate::model::frame::{RawFrame, RgbaImage};
use crate::model::pixel::PixelFormat;
use rayon::prelude::*;

const MASK_10BIT: u32 = 0x3ff;
const MASK_2BIT: u32 = 0x3;
const OPAQUE_ALPHA: u8 = 255;

const SHIFT_CH0: u32 = 0;
const SHIFT_CH1: u32 = 10;
const SHIFT_CH2: u32 = 20;
const SHIFT_ALPHA: u32 = 30;

/// Scales a 10-bit color channel [0, 1023] down to 8-bit [0, 255] with rounding.
#[inline(always)]
const fn scale_10_to_8(v: u32) -> u8 {
    ((v * 255 + 511) / 1023) as u8
}

/// Scales a 2-bit alpha channel [0, 3] up to 8-bit [0, 255] (multiplied by 85).
#[inline(always)]
const fn scale_2_to_8(v: u32) -> u8 {
    (v * 85) as u8
}

/// Swizzles SDR pixel data (both 8-bit and 10-bit SDR) into RGBA.
/// Parallelized over scanlines using Rayon.
pub fn swizzle_sdr(raw: &RawFrame<'_>, dst: &mut RgbaImage) -> Result<(), MilkError> {
    let width = raw.width as usize;
    let height = raw.height as usize;
    let src_stride = raw.stride as usize;
    let dst_stride = dst.row_bytes();
    let y_invert = raw.y_invert;

    dst.data
        .par_chunks_exact_mut(dst_stride)
        .enumerate()
        .for_each(|(y, dst_row)| {
            let src_y = if y_invert { height - 1 - y } else { y };
            let src_offset = src_y * src_stride;
            let src_bytes = &raw.data[src_offset..src_offset + (width * 4)];

            let (src_pixels, _) = src_bytes.as_chunks::<4>();
            let (dst_pixels, _) = dst_row.as_chunks_mut::<4>();

            match raw.format {
                // 8-bit SDR formats
                PixelFormat::Xrgb8888 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        dst_px[0] = src_px[2];
                        dst_px[1] = src_px[1];
                        dst_px[2] = src_px[0];
                        dst_px[3] = OPAQUE_ALPHA;
                    }
                }
                PixelFormat::Argb8888 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        dst_px[0] = src_px[2];
                        dst_px[1] = src_px[1];
                        dst_px[2] = src_px[0];
                        dst_px[3] = src_px[3];
                    }
                }
                PixelFormat::Xbgr8888 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        dst_px[0] = src_px[0];
                        dst_px[1] = src_px[1];
                        dst_px[2] = src_px[2];
                        dst_px[3] = OPAQUE_ALPHA;
                    }
                }
                PixelFormat::Abgr8888 | PixelFormat::Rgba8888 => {
                    dst_row[..width * 4].copy_from_slice(src_bytes);
                }
                PixelFormat::Bgra8888 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        dst_px[0] = src_px[2];
                        dst_px[1] = src_px[1];
                        dst_px[2] = src_px[0];
                        dst_px[3] = src_px[3];
                    }
                }

                // 10-bit SDR formats: scale 10-bit down to 8-bit without applying tonemapping
                PixelFormat::Xrgb2101010 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        let px = u32::from_ne_bytes(*src_px);
                        dst_px[0] = scale_10_to_8((px >> SHIFT_CH2) & MASK_10BIT);
                        dst_px[1] = scale_10_to_8((px >> SHIFT_CH1) & MASK_10BIT);
                        dst_px[2] = scale_10_to_8((px >> SHIFT_CH0) & MASK_10BIT);
                        dst_px[3] = OPAQUE_ALPHA;
                    }
                }
                PixelFormat::Argb2101010 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        let px = u32::from_ne_bytes(*src_px);
                        dst_px[0] = scale_10_to_8((px >> SHIFT_CH2) & MASK_10BIT);
                        dst_px[1] = scale_10_to_8((px >> SHIFT_CH1) & MASK_10BIT);
                        dst_px[2] = scale_10_to_8((px >> SHIFT_CH0) & MASK_10BIT);
                        dst_px[3] = scale_2_to_8((px >> SHIFT_ALPHA) & MASK_2BIT);
                    }
                }
                PixelFormat::Xbgr2101010 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        let px = u32::from_ne_bytes(*src_px);
                        dst_px[0] = scale_10_to_8((px >> SHIFT_CH0) & MASK_10BIT);
                        dst_px[1] = scale_10_to_8((px >> SHIFT_CH1) & MASK_10BIT);
                        dst_px[2] = scale_10_to_8((px >> SHIFT_CH2) & MASK_10BIT);
                        dst_px[3] = OPAQUE_ALPHA;
                    }
                }
                PixelFormat::Abgr2101010 => {
                    for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                        let px = u32::from_ne_bytes(*src_px);
                        dst_px[0] = scale_10_to_8((px >> SHIFT_CH0) & MASK_10BIT);
                        dst_px[1] = scale_10_to_8((px >> SHIFT_CH1) & MASK_10BIT);
                        dst_px[2] = scale_10_to_8((px >> SHIFT_CH2) & MASK_10BIT);
                        dst_px[3] = scale_2_to_8((px >> SHIFT_ALPHA) & MASK_2BIT);
                    }
                }
                _ => {}
            }
        });

    Ok(())
}
