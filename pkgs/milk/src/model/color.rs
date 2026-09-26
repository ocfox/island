pub const WP_COLOR_MANAGER_V1_PRIMARIES_SRGB: u32 = 1;
pub const WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ: u32 = 11;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ColorInfo {
    pub has_tf: bool,
    pub tf_named: u32,
    pub has_primaries: bool,
    pub primaries_named: u32,
    pub has_luminances: bool,
    pub max_lum: f64,
    pub reference_lum: f64,
}

impl Default for ColorInfo {
    fn default() -> Self {
        Self {
            has_tf: false,
            tf_named: 0,
            has_primaries: false,
            primaries_named: 0,
            has_luminances: false,
            max_lum: 0.0,
            reference_lum: 203.0,
        }
    }
}

impl ColorInfo {
    #[inline]
    pub fn needs_tonemap(&self) -> bool {
        self.has_tf && self.tf_named == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ
    }
}
