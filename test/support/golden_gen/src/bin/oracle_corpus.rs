use fsrs::{current_retrievability, FSRSItem, FSRSReview, MemoryState, DEFAULT_PARAMETERS, FSRS};
use serde::Serialize;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::env;
use std::error::Error;
use std::fs::{self, File};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};

const SCHEMA_VERSION: u32 = 1;
const GENERATOR_VERSION: u32 = 1;
const DEFAULT_SEED: u64 = 0x4653_5253_0006_0601;
const TOTAL_CASES: usize = 4096;
const COUNTS: [(&str, usize); 4] = [
    ("next_states", 1536),
    ("memory_state", 1024),
    ("next_interval", 1024),
    ("current_retrievability", 512),
];

const CLAMP_RANGES: [(f32, f32); 21] = [
    (0.001, 100.0),
    (0.001, 100.0),
    (0.001, 100.0),
    (0.001, 100.0),
    (1.0, 10.0),
    (0.001, 4.0),
    (0.001, 4.0),
    (0.001, 0.75),
    (0.0, 4.5),
    (0.0, 0.8),
    (0.001, 3.5),
    (0.001, 5.0),
    (0.001, 0.25),
    (0.001, 0.9),
    (0.0, 4.0),
    (0.0, 1.0),
    (1.0, 6.0),
    (0.0, 2.0),
    (0.0, 2.0),
    (0.0, 0.8),
    (0.1, 0.8),
];
const STABILITY_EDGES: [f32; 6] = [0.001, 0.01, 1.0, 10.0, 100.0, 36_500.0];
const DIFFICULTY_EDGES: [f32; 3] = [1.0, 5.0, 10.0];
const RETENTION_EDGES: [f32; 9] = [1.0, 0.999, 0.99, 0.95, 0.9, 0.8, 0.7, 0.5, 0.1];
const DAY_EDGES: [u32; 8] = [0, 1, 2, 7, 30, 365, 3_650, u32::MAX];
const FRACTIONAL_DAY_EDGES: [f32; 8] = [0.0, 0.001, 0.5, 1.0, 10.0, 100.0, 36_500.0, 1_000_000.0];
const HISTORY_LENGTHS: [usize; 6] = [1, 2, 3, 10, 100, 1_000];

#[derive(Clone, Debug, Serialize)]
struct Meta {
    #[serde(rename = "type")]
    record_type: &'static str,
    schema_version: u32,
    generator_version: u32,
    crate_version: &'static str,
    seed: String,
    case_count: usize,
    counts: BTreeMap<String, usize>,
    default_parameters: Vec<f32>,
}

#[derive(Clone, Debug, Serialize)]
struct Case {
    #[serde(rename = "type")]
    record_type: &'static str,
    id: String,
    kind: &'static str,
    input: Value,
    expected: Value,
}

#[derive(Clone, Debug)]
struct Corpus {
    meta: Meta,
    cases: Vec<Case>,
}

#[derive(Clone, Debug)]
struct Options {
    seed: u64,
    case_id: Option<String>,
    output: Option<PathBuf>,
}

#[derive(Clone, Debug)]
struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut value = self.state;
        value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        value ^ (value >> 31)
    }

    fn index(&mut self, length: usize) -> usize {
        (self.next_u64() % length as u64) as usize
    }

    fn unit(&mut self) -> f32 {
        ((self.next_u64() >> 40) as u32) as f32 / 16_777_216.0
    }

    fn between(&mut self, low: f32, high: f32) -> f32 {
        low + ((high - low) * self.unit())
    }

    fn float_bits_between(&mut self, low: f32, high: f32) -> f32 {
        debug_assert!(low > 0.0 && low <= high && high.is_finite());
        let low_bits = low.to_bits();
        let span = u64::from(high.to_bits() - low_bits) + 1;
        f32::from_bits(low_bits + (self.next_u64() % span) as u32)
    }
}

fn expected_counts() -> BTreeMap<String, usize> {
    COUNTS
        .into_iter()
        .map(|(kind, count)| (kind.to_string(), count))
        .collect()
}

fn generate(seed: u64) -> Corpus {
    let mut rng = SplitMix64::new(seed);
    let mut cases = Vec::with_capacity(TOTAL_CASES);
    let mut global_index = 0;

    for index in 0..COUNTS[0].1 {
        cases.push(next_states_case(index, global_index, &mut rng));
        global_index += 1;
    }
    for index in 0..COUNTS[1].1 {
        cases.push(memory_state_case(index, global_index, &mut rng));
        global_index += 1;
    }
    for index in 0..COUNTS[2].1 {
        cases.push(next_interval_case(index, global_index, &mut rng));
        global_index += 1;
    }
    for index in 0..COUNTS[3].1 {
        cases.push(retrievability_case(index, global_index, &mut rng));
        global_index += 1;
    }

    Corpus {
        meta: Meta {
            record_type: "meta",
            schema_version: SCHEMA_VERSION,
            generator_version: GENERATOR_VERSION,
            crate_version: "6.6.1",
            seed: format!("0x{seed:016x}"),
            case_count: cases.len(),
            counts: expected_counts(),
            default_parameters: DEFAULT_PARAMETERS.to_vec(),
        },
        cases,
    }
}

fn next_states_case(index: usize, global_index: usize, rng: &mut SplitMix64) -> Case {
    let parameters = parameters_for(global_index, rng);
    let fsrs = fsrs_for(parameters.as_ref());
    let memory = if index.is_multiple_of(8) {
        None
    } else {
        Some(MemoryState {
            stability: stability_for(index, rng),
            difficulty: difficulty_for(index, rng),
        })
    };
    let desired_retention = retention_for(index, rng);
    let days_elapsed = days_for(index, rng);
    let states = fsrs
        .next_states(memory, desired_retention, days_elapsed)
        .unwrap();

    Case {
        record_type: "case",
        id: format!("next_states/{index:04}"),
        kind: "next_states",
        input: json!({
            "parameters": parameters_value(parameters.as_ref()),
            "memory": memory.map(memory_value),
            "desired_retention": desired_retention,
            "days_elapsed": days_elapsed,
        }),
        expected: json!({
            "again": item_value(&states.again),
            "hard": item_value(&states.hard),
            "good": item_value(&states.good),
            "easy": item_value(&states.easy),
        }),
    }
}

fn memory_state_case(index: usize, global_index: usize, rng: &mut SplitMix64) -> Case {
    let parameters = parameters_for(global_index, rng);
    let fsrs = fsrs_for(parameters.as_ref());
    let length = if index < 768 {
        HISTORY_LENGTHS[index % HISTORY_LENGTHS.len()]
    } else {
        4 + rng.index(997)
    };
    let mut reviews = Vec::with_capacity(length);
    for review_index in 0..length {
        let rating = 1 + rng.index(4) as u32;
        let delta_t = if review_index == 0 || review_index.is_multiple_of(5) {
            0
        } else {
            days_for(index + review_index, rng)
        };
        reviews.push(FSRSReview { rating, delta_t });
    }
    let state = fsrs
        .memory_state(
            FSRSItem {
                reviews: reviews.clone(),
            },
            None,
        )
        .unwrap();

    Case {
        record_type: "case",
        id: format!("memory_state/{index:04}"),
        kind: "memory_state",
        input: json!({
            "parameters": parameters_value(parameters.as_ref()),
            "reviews": reviews.iter().map(|review| json!({"rating": review.rating, "delta_t": review.delta_t})).collect::<Vec<_>>(),
        }),
        expected: memory_value(state),
    }
}

fn next_interval_case(index: usize, global_index: usize, rng: &mut SplitMix64) -> Case {
    let parameters = parameters_for(global_index, rng);
    let fsrs = fsrs_for(parameters.as_ref());
    let stability = stability_for(index, rng);
    let desired_retention = retention_for(index, rng);
    let interval = fsrs.next_interval(Some(stability), desired_retention, 3);

    Case {
        record_type: "case",
        id: format!("next_interval/{index:04}"),
        kind: "next_interval",
        input: json!({
            "parameters": parameters_value(parameters.as_ref()),
            "stability": stability,
            "desired_retention": desired_retention,
        }),
        expected: json!({"interval": interval}),
    }
}

fn retrievability_case(index: usize, global_index: usize, rng: &mut SplitMix64) -> Case {
    let parameters = parameters_for(global_index, rng);
    let state = MemoryState {
        stability: stability_for(index, rng),
        difficulty: difficulty_for(index, rng),
    };
    let days_elapsed = fractional_days_for(index, rng);
    let decay = parameters
        .as_ref()
        .map_or(DEFAULT_PARAMETERS[20], |weights| weights[20]);
    let retrievability = current_retrievability(state, days_elapsed, decay);

    Case {
        record_type: "case",
        id: format!("current_retrievability/{index:04}"),
        kind: "current_retrievability",
        input: json!({
            "parameters": parameters_value(parameters.as_ref()),
            "memory": memory_value(state),
            "days_elapsed": days_elapsed,
        }),
        expected: json!({"retrievability": retrievability}),
    }
}

fn parameters_for(index: usize, rng: &mut SplitMix64) -> Option<[f32; 21]> {
    match index % 4 {
        0 | 1 => None,
        2 => {
            let mut parameters = DEFAULT_PARAMETERS;
            let boundary_index = index / 4;
            let weight_index = boundary_index % CLAMP_RANGES.len();
            let use_maximum = (boundary_index / CLAMP_RANGES.len()) % 2 == 1;
            parameters[weight_index] = if use_maximum {
                CLAMP_RANGES[weight_index].1
            } else {
                CLAMP_RANGES[weight_index].0
            };
            Some(parameters)
        }
        3 => {
            let mut parameters = [0.0; 21];
            for (weight, (low, high)) in parameters.iter_mut().zip(CLAMP_RANGES) {
                *weight = rng.between(low, high);
            }
            Some(parameters)
        }
        _ => unreachable!(),
    }
}

fn fsrs_for(parameters: Option<&[f32; 21]>) -> FSRS {
    FSRS::new(parameters.map_or(DEFAULT_PARAMETERS.as_slice(), |weights| weights.as_slice()))
        .unwrap()
}

fn stability_for(index: usize, rng: &mut SplitMix64) -> f32 {
    if index % 8 < STABILITY_EDGES.len() {
        STABILITY_EDGES[index % STABILITY_EDGES.len()]
    } else {
        rng.float_bits_between(0.001, 36_500.0)
    }
}

fn difficulty_for(index: usize, rng: &mut SplitMix64) -> f32 {
    if index % 4 < DIFFICULTY_EDGES.len() {
        DIFFICULTY_EDGES[index % DIFFICULTY_EDGES.len()]
    } else {
        rng.between(1.0, 10.0).clamp(1.0, 10.0)
    }
}

fn retention_for(index: usize, rng: &mut SplitMix64) -> f32 {
    if index % 12 < RETENTION_EDGES.len() {
        RETENTION_EDGES[index % RETENTION_EDGES.len()]
    } else {
        rng.between(0.1, 1.0).clamp(0.1, 1.0)
    }
}

fn days_for(index: usize, rng: &mut SplitMix64) -> u32 {
    if index % 12 < DAY_EDGES.len() {
        DAY_EDGES[index % DAY_EDGES.len()]
    } else {
        rng.next_u64() as u32
    }
}

fn fractional_days_for(index: usize, rng: &mut SplitMix64) -> f32 {
    if index % 12 < FRACTIONAL_DAY_EDGES.len() {
        FRACTIONAL_DAY_EDGES[index % FRACTIONAL_DAY_EDGES.len()]
    } else {
        rng.float_bits_between(0.001, 1_000_000.0)
    }
}

fn parameters_value(parameters: Option<&[f32; 21]>) -> Value {
    parameters.map_or(Value::Null, |weights| json!(weights.to_vec()))
}

fn memory_value(memory: MemoryState) -> Value {
    json!({"stability": memory.stability, "difficulty": memory.difficulty})
}

fn item_value(item: &fsrs::ItemState) -> Value {
    json!({
        "stability": item.memory.stability,
        "difficulty": item.memory.difficulty,
        "interval": item.interval,
    })
}

fn select_case(mut corpus: Corpus, case_id: &str) -> Result<Corpus, String> {
    let selected = corpus
        .cases
        .into_iter()
        .find(|case| case.id == case_id)
        .ok_or_else(|| format!("unknown case id {case_id:?}"))?;
    corpus.meta.case_count = 1;
    corpus.meta.counts = BTreeMap::from([(selected.kind.to_string(), 1)]);
    corpus.cases = vec![selected];
    Ok(corpus)
}

fn serialize(corpus: &Corpus) -> Vec<u8> {
    let mut output = Vec::new();
    serde_json::to_writer(&mut output, &corpus.meta).unwrap();
    output.push(b'\n');
    for case in &corpus.cases {
        serde_json::to_writer(&mut output, case).unwrap();
        output.push(b'\n');
    }
    output
}

fn parse_options() -> Result<Options, String> {
    let mut options = Options {
        seed: DEFAULT_SEED,
        case_id: None,
        output: None,
    };
    let mut args = env::args().skip(1);
    while let Some(argument) = args.next() {
        match argument.as_str() {
            "--seed" => {
                let raw = args
                    .next()
                    .ok_or_else(|| "--seed requires a value".to_string())?;
                options.seed = parse_seed(&raw)?;
            }
            "--case" => {
                options.case_id = Some(
                    args.next()
                        .ok_or_else(|| "--case requires an ID".to_string())?,
                )
            }
            "--output" => {
                options.output = Some(PathBuf::from(
                    args.next()
                        .ok_or_else(|| "--output requires a path".to_string())?,
                ))
            }
            _ => return Err(format!("unknown argument {argument:?}")),
        }
    }
    Ok(options)
}

fn parse_seed(raw: &str) -> Result<u64, String> {
    if let Some(hex) = raw.strip_prefix("0x") {
        u64::from_str_radix(hex, 16).map_err(|error| format!("invalid hexadecimal seed: {error}"))
    } else {
        raw.parse::<u64>()
            .map_err(|error| format!("invalid decimal seed: {error}"))
    }
}

fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    let temporary = path.with_extension(format!("tmp.{}", std::process::id()));
    {
        let file = File::create(&temporary)?;
        let mut writer = BufWriter::new(file);
        writer.write_all(contents)?;
        writer.flush()?;
    }
    fs::rename(temporary, path)
}

fn run() -> Result<(), Box<dyn Error>> {
    let options =
        parse_options().map_err(|error| io::Error::new(io::ErrorKind::InvalidInput, error))?;
    let mut corpus = generate(options.seed);
    if let Some(case_id) = options.case_id.as_deref() {
        corpus = select_case(corpus, case_id)
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidInput, error))?;
    }
    let contents = serialize(&corpus);
    if let Some(path) = options.output {
        write_atomic(&path, &contents)?;
    } else {
        io::stdout().write_all(&contents)?;
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("oracle_corpus: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn splitmix64_sequence_is_stable() {
        let mut rng = SplitMix64::new(0);
        assert_eq!(rng.next_u64(), 0xe220_a839_7b1d_cdaf);
        assert_eq!(rng.next_u64(), 0x6e78_9e6a_a1b9_65f4);
    }

    #[test]
    fn positive_float_sampling_is_defined_by_bits() {
        let low = 0.001_f32;
        let high = 36_500.0_f32;
        let span = u64::from(high.to_bits() - low.to_bits()) + 1;
        let expected_bits = low.to_bits() + (0xe220_a839_7b1d_cdaf % span) as u32;
        let mut rng = SplitMix64::new(0);
        assert_eq!(rng.float_bits_between(low, high).to_bits(), expected_bits);
    }

    #[test]
    fn default_corpus_has_exact_counts_and_unique_ids() {
        let corpus = generate(DEFAULT_SEED);
        assert_eq!(corpus.meta.case_count, TOTAL_CASES);
        assert_eq!(corpus.meta.counts, expected_counts());
        assert_eq!(corpus.cases.len(), TOTAL_CASES);

        let ids: HashSet<_> = corpus.cases.iter().map(|case| case.id.as_str()).collect();
        assert_eq!(ids.len(), TOTAL_CASES);
    }

    #[test]
    fn corpus_contains_previous_blind_spots() {
        let corpus = generate(DEFAULT_SEED);
        assert!(corpus.cases.iter().any(|case| {
            case.input
                .get("desired_retention")
                .and_then(|value| value.as_f64())
                .is_some_and(|value| value > 0.99)
        }));
        assert!(corpus
            .cases
            .iter()
            .any(|case| contains_number(&case.input, "stability", 0.001)));
        assert!(corpus.cases.iter().any(|case| {
            case.input
                .get("reviews")
                .and_then(|value| value.as_array())
                .is_some_and(|reviews| reviews.len() > 3)
        }));
        assert!(corpus.cases.iter().any(|case| {
            case.input
                .get("parameters")
                .and_then(|value| value.as_array())
                .is_some_and(|parameters| {
                    parameters
                        .first()
                        .and_then(|value| value.as_f64())
                        .is_some_and(|weight| {
                            (weight - f64::from(DEFAULT_PARAMETERS[0])).abs() > f64::EPSILON
                        })
                })
        }));
    }

    #[test]
    fn same_seed_is_byte_reproducible() {
        assert_eq!(
            serialize(&generate(DEFAULT_SEED)),
            serialize(&generate(DEFAULT_SEED))
        );
    }

    #[test]
    fn selecting_a_case_rewrites_metadata_counts() {
        let selected = select_case(generate(DEFAULT_SEED), "next_interval/0000").unwrap();
        assert_eq!(selected.meta.case_count, 1);
        assert_eq!(selected.meta.counts.get("next_interval"), Some(&1));
        assert_eq!(selected.cases.len(), 1);
        assert_eq!(selected.cases[0].id, "next_interval/0000");
    }

    fn contains_number(input: &Value, key: &str, expected: f64) -> bool {
        input
            .get(key)
            .and_then(|value| value.as_f64())
            .is_some_and(|value| (value - expected).abs() < 1e-9)
            || input
                .get("memory")
                .and_then(|value| value.get(key))
                .and_then(|value| value.as_f64())
                .is_some_and(|value| (value - expected).abs() < 1e-9)
    }
}
