use crate::model::frame::{FilteredScanlines, RgbaImage};
use rayon::prelude::*;

const PNG_FILTER_SUB: u8 = 1;
const BYTES_PER_PIXEL: usize = 4;

/// PNG Filter Type 1: Sub
/// Computes `Sub(x) = Raw(x) - Raw(x - bpp)` with wrapping subtraction.
///
/// Parallelized per row using Rayon.
pub fn apply_sub_filter(img: &RgbaImage) -> FilteredScanlines {
    let mut filtered = FilteredScanlines::new(img.width, img.height);
    let line_len = filtered.line_bytes();
    let row_len = img.row_bytes();

    filtered
        .data
        .par_chunks_exact_mut(line_len)
        .enumerate()
        .for_each(|(y, dst_line)| {
            let src_row = img.row_slice(y);

            // Filter type 1 = Sub
            dst_line[0] = PNG_FILTER_SUB;

            // First pixel (4 bytes): left pixel is zero
            dst_line[1..1 + BYTES_PER_PIXEL].copy_from_slice(&src_row[..BYTES_PER_PIXEL]);

            // Remaining pixels: Sub(x) = Raw(x) - Raw(x - 4)
            let curr_slice = &src_row[BYTES_PER_PIXEL..];
            let prev_slice = &src_row[..row_len - BYTES_PER_PIXEL];
            let dst_slice = &mut dst_line[1 + BYTES_PER_PIXEL..1 + row_len];

            for (dst, (&curr, &prev)) in dst_slice.iter_mut().zip(curr_slice.iter().zip(prev_slice))
            {
                *dst = curr.wrapping_sub(prev);
            }
        });

    filtered
}
