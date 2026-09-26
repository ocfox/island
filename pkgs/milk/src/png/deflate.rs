use crate::model::error::MilkError;
use libdeflater::{CompressionLvl, Compressor};

/// Creates a new libdeflater `Compressor` for the specified compression level (1-9).
pub fn create_compressor(level: u32) -> Result<Compressor, MilkError> {
    let lvl = CompressionLvl::new(level as i32)
        .map_err(|_| MilkError::Compression(format!("Invalid compression level {level}")))?;
    Ok(Compressor::new(lvl))
}
