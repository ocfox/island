use crate::model::color::{ColorInfo, WP_COLOR_MANAGER_V1_PRIMARIES_SRGB};
use crate::model::error::MilkError;
use crate::model::frame::{RawFrame, RgbaImage};
use crate::model::pixel::PixelFormat;
use rayon::prelude::*;

// SMPTE ST 2084 constants
const PQ_M1: f64 = 2610.0 / 16384.0;
const PQ_M2: f64 = 2523.0 / 4096.0 * 128.0;
const PQ_C1: f64 = 3424.0 / 4096.0;
const PQ_C2: f64 = 2413.0 / 4096.0 * 32.0;
const PQ_C3: f64 = 2392.0 / 4096.0 * 32.0;

const ST2084_PEAK_LUMINANCE: f64 = 10000.0;
const BT2408_REFERENCE_LUMINANCE: f64 = 203.0;
const DECODE_LUT_SIZE: usize = 1024;
const OPAQUE_ALPHA: u8 = 255;

const MASK_10BIT: u32 = 0x3ff;
const SHIFT_CH0: u32 = 0;
const SHIFT_CH1: u32 = 10;
const SHIFT_CH2: u32 = 20;

// Inverse of the PQ OETF: a signal value in [0, 1] to absolute luminance in
// cd/m², where 1.0 corresponds to 10000 cd/m².
#[inline]
fn pq_to_luminance(e: f64) -> f64 {
    let ep = e.powf(1.0 / PQ_M2);
    let mut num = ep - PQ_C1;
    if num < 0.0 {
        num = 0.0;
    }
    ST2084_PEAK_LUMINANCE * (num / (PQ_C2 - PQ_C3 * ep)).powf(1.0 / PQ_M1)
}

// Compositors encode SDR output with a pure 2.2 power curve rather than the
// piecewise sRGB one, so using it here is what makes a capture of an HDR output
// match a capture of the same content with HDR turned off.
const SDR_GAMMA: f64 = 2.2;

#[inline]
fn sdr_encode(v: f64) -> f64 {
    v.powf(1.0 / SDR_GAMMA)
}

// BT.2020 to BT.709 primaries, in linear light
const BT2020_TO_SRGB: [[f64; 3]; 3] = [
    [1.6605, -0.5876, -0.0728],
    [-0.1246, 1.1329, -0.0083],
    [-0.0182, -0.1006, 1.1187],
];

const ENCODE_LUT_SIZE: usize = 4096;

pub struct ToneMapper {
    decode_lut: [f64; DECODE_LUT_SIZE],
    encode_lut: [u8; ENCODE_LUT_SIZE],
    convert_primaries: bool,
}

impl ToneMapper {
    pub fn new(color: &ColorInfo) -> Self {
        // Diffuse white sits at the reference luminance, so scaling by it puts
        // ordinary SDR content at 1.0. Anything brighter is a highlight that
        // cannot be represented in sRGB and gets clipped below.
        let mut reference_lum = if color.has_luminances {
            color.reference_lum
        } else {
            BT2408_REFERENCE_LUMINANCE
        };
        if reference_lum <= 0.0 {
            reference_lum = BT2408_REFERENCE_LUMINANCE;
        }

        // The source is 10-bit, so the electro-optical transfer function is
        // exactly representable as a table
        let mut decode_lut = [0.0f64; DECODE_LUT_SIZE];
        for (i, slot) in decode_lut.iter_mut().enumerate() {
            *slot = pq_to_luminance(i as f64 / (DECODE_LUT_SIZE - 1) as f64) / reference_lum;
        }

        // The encode step only feeds an 8-bit result, so a table indexed by the
        // clipped linear value is accurate enough and avoids a pow() per channel
        let mut encode_lut = [0u8; ENCODE_LUT_SIZE];
        for (i, slot) in encode_lut.iter_mut().enumerate() {
            let v = sdr_encode(i as f64 / (ENCODE_LUT_SIZE - 1) as f64);
            *slot = (v * 255.0).round().clamp(0.0, 255.0) as u8;
        }

        let convert_primaries =
            !color.has_primaries || color.primaries_named != WP_COLOR_MANAGER_V1_PRIMARIES_SRGB;

        Self {
            decode_lut,
            encode_lut,
            convert_primaries,
        }
    }

    pub fn apply(&self, raw: &RawFrame<'_>, dst: &mut RgbaImage) -> Result<(), MilkError> {
        let width = raw.width as usize;
        let height = raw.height as usize;
        let src_stride = raw.stride as usize;
        let dst_stride = dst.row_bytes();
        let y_invert = raw.y_invert;

        let is_xbgr = matches!(
            raw.format,
            PixelFormat::Xbgr2101010 | PixelFormat::Abgr2101010
        );
        let convert_primaries = self.convert_primaries;
        let decode = &self.decode_lut;
        let encode = &self.encode_lut;

        dst.data
            .par_chunks_exact_mut(dst_stride)
            .enumerate()
            .for_each(|(y, dst_row)| {
                let src_y = if y_invert { height - 1 - y } else { y };
                let src_offset = src_y * src_stride;
                let src_bytes = &raw.data[src_offset..src_offset + (width * 4)];

                let (src_pixels, _) = src_bytes.as_chunks::<4>();
                let (dst_pixels, _) = dst_row.as_chunks_mut::<4>();

                for (src_px, dst_px) in src_pixels.iter().zip(dst_pixels.iter_mut()) {
                    let px = u32::from_ne_bytes(*src_px);

                    let mut rgb = if is_xbgr {
                        [
                            decode[((px >> SHIFT_CH0) & MASK_10BIT) as usize],
                            decode[((px >> SHIFT_CH1) & MASK_10BIT) as usize],
                            decode[((px >> SHIFT_CH2) & MASK_10BIT) as usize],
                        ]
                    } else {
                        [
                            decode[((px >> SHIFT_CH2) & MASK_10BIT) as usize],
                            decode[((px >> SHIFT_CH1) & MASK_10BIT) as usize],
                            decode[((px >> SHIFT_CH0) & MASK_10BIT) as usize],
                        ]
                    };

                    if convert_primaries {
                        let input = rgb;
                        for c in 0..3 {
                            rgb[c] = BT2020_TO_SRGB[c][0] * input[0]
                                + BT2020_TO_SRGB[c][1] * input[1]
                                + BT2020_TO_SRGB[c][2] * input[2];
                        }
                    }

                    for (c, &val) in rgb.iter().enumerate() {
                        let v = val.clamp(0.0, 1.0);
                        let idx = (v * (ENCODE_LUT_SIZE - 1) as f64).round() as usize;
                        dst_px[c] = encode[idx];
                    }
                    dst_px[3] = OPAQUE_ALPHA;
                }
            });

        Ok(())
    }
}
