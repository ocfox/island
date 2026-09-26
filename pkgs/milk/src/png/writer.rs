use super::deflate::create_compressor;
use crate::model::error::MilkError;

pub const PNG_SIGNATURE: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];

const BIT_DEPTH_8: u8 = 8;
const COLOR_TYPE_RGBA: u8 = 6;
const COMPRESSION_DEFLATE: u8 = 0;
const FILTER_STANDARD: u8 = 0;
const INTERLACE_NONE: u8 = 0;
const SRGB_PERCEPTUAL: u8 = 0;

const IHDR_DATA_LEN: usize = 13;
const CHUNK_OVERHEAD: usize = 12; // 4 (len) + 4 (type) + 4 (crc)
const IHDR_CHUNK_SIZE: usize = IHDR_DATA_LEN + CHUNK_OVERHEAD; // 25
const SRGB_CHUNK_SIZE: usize = 1 + CHUNK_OVERHEAD; // 13
const IEND_CHUNK_SIZE: usize = CHUNK_OVERHEAD; // 12
const IDAT_HEADER_SIZE: usize = 8; // 4 (len) + 4 (type)
const CRC_SIZE: usize = 4;

#[inline]
fn write_chunk(buf: &mut Vec<u8>, chunk_type: &[u8; 4], data: &[u8]) {
    let len = data.len() as u32;
    buf.extend_from_slice(&len.to_be_bytes());
    buf.extend_from_slice(chunk_type);
    buf.extend_from_slice(data);

    let mut hasher = crc32fast::Hasher::new();
    hasher.update(chunk_type);
    hasher.update(data);
    let crc = hasher.finalize();
    buf.extend_from_slice(&crc.to_be_bytes());
}

/// Encodes filtered scanlines into complete PNG bytes in a single contiguous buffer.
/// Eliminates intermediate buffer allocation and secondary memcpy copies.
pub fn write_png(
    width: u32,
    height: u32,
    filtered_data: &[u8],
    level: u32,
) -> Result<Vec<u8>, MilkError> {
    let mut compressor = create_compressor(level)?;
    let max_compressed_len = compressor.zlib_compress_bound(filtered_data.len());

    let header_prefix_size =
        PNG_SIGNATURE.len() + IHDR_CHUNK_SIZE + SRGB_CHUNK_SIZE + IDAT_HEADER_SIZE;
    let footer_suffix_size = CRC_SIZE + IEND_CHUNK_SIZE;
    let total_capacity = header_prefix_size + max_compressed_len + footer_suffix_size;

    let mut out = Vec::with_capacity(total_capacity);

    out.extend_from_slice(&PNG_SIGNATURE);

    let mut ihdr_data = [0u8; IHDR_DATA_LEN];
    ihdr_data[0..4].copy_from_slice(&width.to_be_bytes());
    ihdr_data[4..8].copy_from_slice(&height.to_be_bytes());
    ihdr_data[8] = BIT_DEPTH_8;
    ihdr_data[9] = COLOR_TYPE_RGBA;
    ihdr_data[10] = COMPRESSION_DEFLATE;
    ihdr_data[11] = FILTER_STANDARD;
    ihdr_data[12] = INTERLACE_NONE;
    write_chunk(&mut out, b"IHDR", &ihdr_data);

    write_chunk(&mut out, b"sRGB", &[SRGB_PERCEPTUAL]);

    let idat_len_offset = out.len();
    out.extend_from_slice(&[0u8; 4]); // placeholder for payload length
    out.extend_from_slice(b"IDAT");

    let payload_offset = out.len();
    out.resize(payload_offset + max_compressed_len, 0);

    let actual_compressed_len = compressor
        .zlib_compress(filtered_data, &mut out[payload_offset..])
        .map_err(|e| MilkError::Compression(format!("zlib compression failed: {e:?}")))?;

    out.truncate(payload_offset + actual_compressed_len);

    // Fill in actual IDAT length
    let len_bytes = (actual_compressed_len as u32).to_be_bytes();
    out[idat_len_offset..idat_len_offset + 4].copy_from_slice(&len_bytes);

    // Compute CRC over "IDAT" + payload
    let mut hasher = crc32fast::Hasher::new();
    hasher.update(&out[idat_len_offset + 4..out.len()]);
    let idat_crc = hasher.finalize();
    out.extend_from_slice(&idat_crc.to_be_bytes());

    write_chunk(&mut out, b"IEND", &[]);

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_write_png() {
        let scanlines = [1u8, 0, 0, 0, 255]; // Sub filter, 1 black pixel
        let png = write_png(1, 1, &scanlines, 1).unwrap();
        assert_eq!(&png[0..8], &PNG_SIGNATURE);
        // IHDR chunk: length 13, chunk type "IHDR"
        assert_eq!(&png[8..12], &13u32.to_be_bytes());
        assert_eq!(&png[12..16], b"IHDR");
        // Ends with IEND chunk
        assert_eq!(&png[png.len() - 8..png.len() - 4], b"IEND");
    }
}
