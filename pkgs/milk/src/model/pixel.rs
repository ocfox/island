use crate::model::error::MilkError;
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PixelFormat {
    /// 32-bit BGRX (8 bits per channel)
    Xrgb8888,
    /// 32-bit BGRA (8 bits per channel)
    Argb8888,
    /// 32-bit RGBX (8 bits per channel)
    Xbgr8888,
    /// 32-bit RGBA (8 bits per channel)
    Abgr8888,
    /// 32-bit RGBA (8 bits per channel, little-endian DRM RA24)
    Rgba8888,
    /// 32-bit BGRA (8 bits per channel, little-endian DRM BA24)
    Bgra8888,

    /// 10-bit per channel XRGB (DRM_FORMAT_XRGB2101010 / XR30)
    Xrgb2101010,
    /// 10-bit per channel ARGB (DRM_FORMAT_ARGB2101010 / AR30)
    Argb2101010,
    /// 10-bit per channel XBGR (DRM_FORMAT_XBGR2101010 / XB30)
    Xbgr2101010,
    /// 10-bit per channel ABGR (DRM_FORMAT_ABGR2101010 / AB30)
    Abgr2101010,

    Unsupported(u32),
}

impl PixelFormat {
    pub const DRM_FORMAT_ARGB8888: u32 = 0x34325241; // 'AR24'
    pub const DRM_FORMAT_XRGB8888: u32 = 0x34325258; // 'XR24'
    pub const DRM_FORMAT_ABGR8888: u32 = 0x34324241; // 'AB24'
    pub const DRM_FORMAT_XBGR8888: u32 = 0x34324258; // 'XB24'
    pub const DRM_FORMAT_RGBA8888: u32 = 0x34314152; // 'RA24'
    pub const DRM_FORMAT_BGRA8888: u32 = 0x34314142; // 'BA24'

    pub const DRM_FORMAT_ARGB2101010: u32 = 0x30335241; // 'AR30'
    pub const DRM_FORMAT_XRGB2101010: u32 = 0x30335258; // 'XR30'
    pub const DRM_FORMAT_ABGR2101010: u32 = 0x30334241; // 'AB30'
    pub const DRM_FORMAT_XBGR2101010: u32 = 0x30334258; // 'XB30'

    pub fn from_fourcc(fourcc: u32) -> Self {
        match fourcc {
            0 => Self::Argb8888, // wl_shm::format::argb8888
            1 => Self::Xrgb8888, // wl_shm::format::xrgb8888
            Self::DRM_FORMAT_ARGB8888 => Self::Argb8888,
            Self::DRM_FORMAT_XRGB8888 => Self::Xrgb8888,
            Self::DRM_FORMAT_ABGR8888 => Self::Abgr8888,
            Self::DRM_FORMAT_XBGR8888 => Self::Xbgr8888,
            Self::DRM_FORMAT_RGBA8888 => Self::Rgba8888,
            Self::DRM_FORMAT_BGRA8888 => Self::Bgra8888,
            Self::DRM_FORMAT_ARGB2101010 => Self::Argb2101010,
            Self::DRM_FORMAT_XRGB2101010 => Self::Xrgb2101010,
            Self::DRM_FORMAT_ABGR2101010 => Self::Abgr2101010,
            Self::DRM_FORMAT_XBGR2101010 => Self::Xbgr2101010,
            other => Self::Unsupported(other),
        }
    }

    #[inline]
    pub fn is_10bit(&self) -> bool {
        matches!(
            self,
            Self::Xrgb2101010 | Self::Argb2101010 | Self::Xbgr2101010 | Self::Abgr2101010
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Geometry {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

impl FromStr for Geometry {
    type Err = MilkError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let mut words = s.split_whitespace();
        let pos_part = words
            .next()
            .ok_or_else(|| MilkError::InvalidGeometry(s.to_string()))?;
        let size_part = words
            .next()
            .ok_or_else(|| MilkError::InvalidGeometry(s.to_string()))?;

        let (x_str, y_str) = pos_part
            .split_once(',')
            .ok_or_else(|| MilkError::InvalidGeometry(s.to_string()))?;
        let (w_str, h_str) = size_part
            .split_once('x')
            .ok_or_else(|| MilkError::InvalidGeometry(s.to_string()))?;

        let x = x_str
            .parse::<i32>()
            .map_err(|_| MilkError::InvalidGeometry(s.to_string()))?;
        let y = y_str
            .parse::<i32>()
            .map_err(|_| MilkError::InvalidGeometry(s.to_string()))?;
        let width = w_str
            .parse::<u32>()
            .map_err(|_| MilkError::InvalidGeometry(s.to_string()))?;
        let height = h_str
            .parse::<u32>()
            .map_err(|_| MilkError::InvalidGeometry(s.to_string()))?;

        if width == 0 || height == 0 {
            return Err(MilkError::InvalidGeometry(
                "Width and height must be > 0".to_string(),
            ));
        }

        Ok(Self {
            x,
            y,
            width,
            height,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_geometry_parsing() {
        let g: Geometry = "100,200 300x400".parse().unwrap();
        assert_eq!(
            g,
            Geometry {
                x: 100,
                y: 200,
                width: 300,
                height: 400
            }
        );

        // Slurp format with output name suffix
        let g2: Geometry = "0,0 3840x2160 DP-2".parse().unwrap();
        assert_eq!(
            g2,
            Geometry {
                x: 0,
                y: 0,
                width: 3840,
                height: 2160
            }
        );

        // Invalid geometries
        assert!("invalid".parse::<Geometry>().is_err());
        assert!("0,0 0x100".parse::<Geometry>().is_err());
    }

    #[test]
    fn test_pixel_format() {
        assert_eq!(PixelFormat::from_fourcc(0), PixelFormat::Argb8888);
        assert_eq!(PixelFormat::from_fourcc(1), PixelFormat::Xrgb8888);
        assert_eq!(
            PixelFormat::from_fourcc(PixelFormat::DRM_FORMAT_XRGB2101010),
            PixelFormat::Xrgb2101010
        );
        assert!(PixelFormat::Xrgb2101010.is_10bit());
        assert!(!PixelFormat::Xrgb8888.is_10bit());
    }
}
