use crate::model::error::MilkError;
use crate::model::frame::RgbaImage;
use mtpng::encoder::{Encoder, Options};
use mtpng::{CompressionLevel, Filter, Header, Mode};

const DEFAULT_BUFFER_CAPACITY: usize = 16 * 1024 * 1024;

/// Functional pipeline transform: `RgbaImage` -> `PNG Bytes`
/// Uses mtpng for parallel filtering and multithreaded Rayon Deflate encoding.
pub fn encode_png(img: &RgbaImage, level: u32) -> Result<Vec<u8>, MilkError> {
    let mut header = Header::new();
    header
        .set_size(img.width, img.height)
        .map_err(|e| MilkError::Compression(e.to_string()))?;

    let comp_level = match level {
        0..=2 => CompressionLevel::Fast,
        3..=7 => CompressionLevel::Default,
        _ => CompressionLevel::High,
    };

    let mut options = Options::new();
    options
        .set_compression_level(comp_level)
        .map_err(|e| MilkError::Compression(e.to_string()))?;
    options
        .set_filter_mode(Mode::Fixed(Filter::Sub))
        .map_err(|e| MilkError::Compression(e.to_string()))?;

    let initial_capacity = (img.width as usize * img.height as usize).min(DEFAULT_BUFFER_CAPACITY);
    let mut out = Vec::with_capacity(initial_capacity);

    let mut encoder = Encoder::new(&mut out, &options);
    encoder
        .write_header(&header)
        .map_err(|e| MilkError::Compression(e.to_string()))?;
    encoder
        .write_image_rows(&img.data)
        .map_err(|e| MilkError::Compression(e.to_string()))?;
    encoder
        .finish()
        .map_err(|e| MilkError::Compression(e.to_string()))?;

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_png() {
        let mut img = RgbaImage::new(2, 2);
        img.data = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255,
        ];
        let png = encode_png(&img, 1).unwrap();
        assert!(!png.is_empty());
        assert_eq!(&png[0..8], &[137, 80, 78, 71, 13, 10, 26, 10]);
    }
}
