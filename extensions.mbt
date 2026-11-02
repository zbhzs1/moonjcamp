///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub extend Severity with ToJson::{to_json}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
pub extend JcampError with @debug.Debug::{to_repr}

///|
pub extend NumericMode with Eq::{equal, not_equal}

///|
pub extend NumericMode with @debug.Debug::{to_repr}

///|
pub extend NumericMode with ToJson::{to_json}

///|
pub extend Encoding with Eq::{equal, not_equal}

///|
pub extend Encoding with @debug.Debug::{to_repr}

///|
pub extend Encoding with ToJson::{to_json}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with ToJson::{to_json}

///|
pub extend ParseOptions with @debug.Debug::{to_repr}

///|
pub extend ParseOptions with ToJson::{to_json}

///|
pub extend Record with Eq::{equal, not_equal}

///|
pub extend Record with @debug.Debug::{to_repr}

///|
pub extend Record with ToJson::{to_json}

///|
pub extend Record with @json.FromJson::{from_json}

///|
pub extend DataLine with Eq::{equal, not_equal}

///|
pub extend DataLine with @debug.Debug::{to_repr}

///|
pub extend DataLine with ToJson::{to_json}

///|
pub extend DataTable with Eq::{equal, not_equal}

///|
pub extend DataTable with @debug.Debug::{to_repr}

///|
pub extend DataTable with ToJson::{to_json}

///|
pub extend Block with @debug.Debug::{to_repr}

///|
pub extend Block with ToJson::{to_json}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend Document with ToJson::{to_json}

///|
pub extend Point with Eq::{equal, not_equal}

///|
pub extend Point with @debug.Debug::{to_repr}

///|
pub extend Point with ToJson::{to_json}

///|
pub extend Point with @json.FromJson::{from_json}

///|
pub extend Spectrum with @debug.Debug::{to_repr}

///|
pub extend Spectrum with ToJson::{to_json}

///|
pub extend Spectrum with @json.FromJson::{from_json}

///|
pub extend Report with @debug.Debug::{to_repr}

///|
pub extend Report with ToJson::{to_json}

///|
pub extend QualityPolicy with @debug.Debug::{to_repr}

///|
pub extend QualityPolicy with ToJson::{to_json}

///|
pub extend Summary with @debug.Debug::{to_repr}

///|
pub extend Summary with ToJson::{to_json}

///|
pub extend BatchInput with @debug.Debug::{to_repr}

///|
pub extend BatchInput with ToJson::{to_json}

///|
pub extend BatchItem with @debug.Debug::{to_repr}

///|
pub extend BatchItem with ToJson::{to_json}

///|
pub extend BatchReport with @debug.Debug::{to_repr}

///|
pub extend BatchReport with ToJson::{to_json}

///|
pub extend CsvBundle with @debug.Debug::{to_repr}

///|
pub extend CsvBundle with ToJson::{to_json}
