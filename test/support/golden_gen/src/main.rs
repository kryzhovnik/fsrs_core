use fsrs::{FSRS, MemoryState, FSRSItem, FSRSReview, DEFAULT_PARAMETERS, current_retrievability};
use serde_json::{json, Value};

fn item(s: &fsrs::ItemState) -> Value {
    json!({ "stability": s.memory.stability, "difficulty": s.memory.difficulty, "interval": s.interval })
}
fn mem_json(m: Option<MemoryState>) -> Value {
    m.map(|m| json!({"stability": m.stability, "difficulty": m.difficulty})).unwrap_or(Value::Null)
}
fn next_states(name: &str, f: &FSRS, m: Option<MemoryState>, dr: f32, days: u32) -> Value {
    let ns = f.next_states(m, dr, days).unwrap();
    json!({ "name": name, "kind": "next_states",
        "input": {"memory": mem_json(m), "desired_retention": dr, "days_elapsed": days},
        "expected": {"again": item(&ns.again), "hard": item(&ns.hard), "good": item(&ns.good), "easy": item(&ns.easy)} })
}
fn memory_state(name: &str, f: &FSRS, revs: &[(u32, u32)]) -> Value {
    let it = FSRSItem { reviews: revs.iter().map(|&(r, d)| FSRSReview { rating: r, delta_t: d }).collect() };
    let ms = f.memory_state(it, None).unwrap();
    json!({ "name": name, "kind": "memory_state",
        "input": {"reviews": revs.iter().map(|&(r,d)| json!({"rating":r,"delta_t":d})).collect::<Vec<_>>()},
        "expected": {"stability": ms.stability, "difficulty": ms.difficulty} })
}

fn main() {
    let f = FSRS::new(&DEFAULT_PARAMETERS).unwrap();
    let existing = MemoryState { stability: 10.0, difficulty: 5.0 };
    let mut cases: Vec<Value> = vec![];

    cases.push(next_states("new_card_d0",          &f, None, 0.9, 0));
    cases.push(next_states("existing_d7",          &f, Some(existing), 0.9, 7));
    cases.push(next_states("existing_d0_sameday",  &f, Some(existing), 0.9, 0));
    cases.push(next_states("highdiff_d3",          &f, Some(MemoryState{stability:100.0,difficulty:9.5}), 0.9, 3));
    cases.push(next_states("smax_saturate",        &f, Some(MemoryState{stability:36500.0,difficulty:1.0}), 0.9, 1));

    cases.push(memory_state("replay_shortterm", &f, &[(3,0),(3,0),(3,7)]));
    cases.push(memory_state("replay_longterm",  &f, &[(3,0),(3,7),(4,16)]));
    cases.push(memory_state("replay_lapse",     &f, &[(3,0),(1,10),(3,5)]));

    for &(nm, s, dr) in &[("ni_s5_r80",5.0f32,0.8f32),("ni_s5_r95",5.0,0.95),
                          ("ni_s50_r80",50.0,0.8),("ni_s50_r95",50.0,0.95),
                          ("ni_s36500_r80",36500.0,0.8),("ni_s36500_r95",36500.0,0.95)] {
        cases.push(json!({"name":nm,"kind":"next_interval","input":{"stability":s,"desired_retention":dr},
            "expected":{"interval": f.next_interval(Some(s), dr, 3)}}));
    }
    for &(nm, w20, dr) in &[("ni_decaylo_r80",0.1f32,0.8f32),("ni_decayhi_r80",0.8,0.8),
                            ("ni_decaylo_r95",0.1,0.95),("ni_decayhi_r95",0.8,0.95)] {
        let mut p = DEFAULT_PARAMETERS; p[20] = w20;
        let fp = FSRS::new(&p).unwrap();
        cases.push(json!({"name":nm,"kind":"next_interval","input":{"stability":1000.0,"desired_retention":dr,"parameters": p.to_vec()},
            "expected":{"interval": fp.next_interval(Some(1000.0), dr, 3)}}));
    }

    // failure-cap-active: custom w17=w18=2.0 make the post-lapse cap small enough that min() selects it.
    {
        let mut p = DEFAULT_PARAMETERS; p[17] = 2.0; p[18] = 2.0;
        let fp = FSRS::new(&p).unwrap();
        let m = MemoryState { stability: 100.0, difficulty: 5.0 };
        let ns = fp.next_states(Some(m), 0.9, 7).unwrap();
        cases.push(json!({"name":"cap_active_lapse","kind":"next_states",
            "input":{"memory": mem_json(Some(m)), "desired_retention":0.9, "days_elapsed":7, "parameters": p.to_vec()},
            "expected":{"again": item(&ns.again), "hard": item(&ns.hard), "good": item(&ns.good), "easy": item(&ns.easy)}}));
    }

    for &(nm, days) in &[("retr_t0",0.0f32),("retr_t10",10.0),("retr_large",100.0)] {
        cases.push(json!({"name":nm,"kind":"current_retrievability",
            "input":{"memory":{"stability":10.0,"difficulty":5.0},"days_elapsed":days},
            "expected":{"retrievability": current_retrievability(existing, days, DEFAULT_PARAMETERS[20])}}));
    }

    println!("{}", serde_json::to_string_pretty(&json!({
        "crate_version":"6.6.1","default_parameters": DEFAULT_PARAMETERS.to_vec(),"cases":cases})).unwrap());
}
