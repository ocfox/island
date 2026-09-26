use crate::model::pixel::PixelFormat;

/// Raw frame buffer directly mapped from Wayland compositor shared memory (memfd).
pub struct RawFrame<'a> {
    pub data: &'a [u8],
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: PixelFormat,
    pub y_invert: bool,
}

/// Contiguous, unpadded 8-bit RGBA image buffer ready for processing.
/// Each pixel is strictly 4 bytes: `[R, G, B, A]`.
/// Memory layout: row-major, tightly packed (`stride == width * 4`).
pub struct RgbaImage {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

impl RgbaImage {
    pub fn new(width: u32, height: u32) -> Self {
        let size = (width as usize)
            .checked_mul(height as usize)
            .and_then(|px| px.checked_mul(4))
            .expect("RgbaImage buffer size overflow");

        Self {
            width,
            height,
            data: vec![0u8; size],
        }
    }

    #[inline]
    pub fn row_bytes(&self) -> usize {
        self.width as usize * 4
    }
}
