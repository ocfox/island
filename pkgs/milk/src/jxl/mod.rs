use crate::model::error::MilkError;
use crate::model::frame::RgbaImage;
use jpegxl_rs::encode::{EncoderFrame, EncoderSpeed};
use jpegxl_rs::encoder_builder;
use jpegxl_rs::ThreadsRunner;

#[derive(Debug, Clone)]
pub struct JxlOptions {
    pub lossless: bool,
    pub speed: EncoderSpeed,
    pub quality: f32,
}

impl Default for JxlOptions {
    fn default() -> Self {
        Self {
            lossless: true,
            speed: EncoderSpeed::Lightning,
            quality: 1.0,
        }
    }
}

pub fn map_speed(speed: u32) -> EncoderSpeed {
    match speed {
        1 => EncoderSpeed::Lightning,
        2 => EncoderSpeed::Thunder,
        3 => EncoderSpeed::Falcon,
        4 => EncoderSpeed::Cheetah,
        5 => EncoderSpeed::Hare,
        6 => EncoderSpeed::Wombat,
        7 => EncoderSpeed::Squirrel,
        8 => EncoderSpeed::Kitten,
        9 => EncoderSpeed::Tortoise,
        _ => EncoderSpeed::Glacier,
    }
}

/// Functional pipeline transform: `RgbaImage` -> `JPEG XL Bytes`
/// Uses libjxl with ThreadsRunner for multithreaded encoding.
pub fn encode_jxl(img: &RgbaImage, options: &JxlOptions) -> Result<Vec<u8>, MilkError> {
    let runner = ThreadsRunner::default();
    let mut encoder = if options.lossless {
        encoder_builder()
            .parallel_runner(&runner)
            .has_alpha(true)
            .speed(options.speed)
            .lossless(true)
            .uses_original_profile(true)
            .build()
    } else {
        encoder_builder()
            .parallel_runner(&runner)
            .has_alpha(true)
            .speed(options.speed)
            .lossless(false)
            .quality(options.quality)
            .build()
    }
    .map_err(|e| MilkError::Compression(e.to_string()))?;

    let frame = EncoderFrame::new(&img.data).num_channels(4);
    encoder
        .encode_frame(&frame, img.width, img.height)
        .map_err(|e| MilkError::Compression(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_jxl() {
        let mut img = RgbaImage::new(2, 2);
        img.data = vec![
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255,
        ];
        let jxl = encode_jxl(&img, &JxlOptions::default()).unwrap();
        assert!(!jxl.is_empty());

        let lossy_opts = JxlOptions {
            lossless: false,
            speed: EncoderSpeed::Lightning,
            quality: 1.0,
        };
        let jxl_lossy = encode_jxl(&img, &lossy_opts).unwrap();
        assert!(!jxl_lossy.is_empty());
    }
}
