pub mod sdr;
pub mod tonemap;

use crate::model::color::ColorInfo;
use crate::model::error::MilkError;
use crate::model::frame::{RawFrame, RgbaImage};

use sdr::swizzle_sdr;
use tonemap::ToneMapper;

/// Functional pipeline transform: `RawFrame` -> `RgbaImage`
/// Strictly follows grim hdr-tonemap.patch:
/// Only apply ST.2084 PQ tonemapping if `color.needs_tonemap()` is true!
/// Otherwise, use fast SDR swizzle (scaling 10-bit SDR to 8-bit SDR).
pub fn process_raw_frame(raw: &RawFrame<'_>, color: &ColorInfo) -> Result<RgbaImage, MilkError> {
    let mut image = RgbaImage::new(raw.width, raw.height);

    if color.needs_tonemap() && raw.format.is_10bit() {
        let tone_mapper = ToneMapper::new(color);
        tone_mapper.apply(raw, &mut image)?;
    } else {
        swizzle_sdr(raw, &mut image)?;
    }

    Ok(image)
}
