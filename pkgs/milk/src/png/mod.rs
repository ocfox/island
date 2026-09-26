pub mod deflate;
pub mod filter;
pub mod writer;

use crate::model::error::MilkError;
use crate::model::frame::RgbaImage;

use filter::apply_sub_filter;
use writer::write_png;

/// Functional pipeline transform: `RgbaImage` -> `PNG Bytes`
/// Applies parallel Sub filtering, libdeflater compression, and chunk assembly in a single contiguous buffer.
pub fn encode_png(img: &RgbaImage, level: u32) -> Result<Vec<u8>, MilkError> {
    let filtered = apply_sub_filter(img);
    write_png(img.width, img.height, &filtered.data, level)
}
