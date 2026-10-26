import pandas as pd

RAW_PATH = "data/raw/global_suicide_rates_real_who_worldbank.csv"
OUT_DIR = "data/processed"

DECADE_BINS = {"10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70plus"}
COARSE_BINS = {"15-19", "15-29", "30-49", "50-69"}

def classify_age_scheme(bracket):
    if bracket == "all_ages":
        return "total"
    elif bracket in DECADE_BINS:
        return "decade"
    elif bracket in COARSE_BINS:
        return "coarse"
    raise ValueError(f"unrecognized age_bracket: {bracket}")

def main():
    df = pd.read_csv(RAW_PATH)
    raw_rows = len(df)

    countries = df[["country_code", "country"]].drop_duplicates()
    assert countries["country_code"].is_unique, "a country_code maps to >1 country name"

    # GDP and population must be constant within a country-year
    conflicts = df.groupby(["country_code", "year"])[
        ["gdp_usd", "gdp_per_capita_usd", "total_country_population"]
    ].nunique()
    assert (conflicts.max() <= 1).all(), "conflicting GDP/population values within a country-year"

    demographics = df[["sex", "age_bracket"]].drop_duplicates().reset_index(drop=True)
    demographics["demographic_id"] = demographics.index + 1
    demographics["age_scheme"] = demographics["age_bracket"].apply(classify_age_scheme)
    demographics["sex_is_total"] = demographics["sex"] == "both"

    df = df.merge(demographics, on=["sex", "age_bracket"])

    socioeconomic_facts = (
        df[["country_code", "year", "gdp_usd", "gdp_per_capita_usd", "total_country_population"]]
        .drop_duplicates(subset=["country_code", "year"])
    )

    socioeconomic_facts["total_country_population"] = (
        socioeconomic_facts["total_country_population"].astype("Int64")
    )

    mortality_facts = df[["country_code", "year", "demographic_id", "suicide_rate_per_100k"]]

    # Integrity checks before writing
    assert len(mortality_facts) == raw_rows, "rows were lost or duplicated during the merge"
    assert not mortality_facts.duplicated(["country_code", "year", "demographic_id"]).any(), \
        "duplicate (country_code, year, demographic_id) keys"

    countries.to_csv(f"{OUT_DIR}/countries.csv", index=False)
    demographics[["demographic_id", "sex", "age_bracket", "age_scheme", "sex_is_total"]].to_csv(
        f"{OUT_DIR}/demographics.csv", index=False
    )
    socioeconomic_facts.to_csv(f"{OUT_DIR}/socioeconomic_facts.csv", index=False)
    mortality_facts.to_csv(f"{OUT_DIR}/mortality_facts.csv", index=False)

    print(f"countries: {len(countries)}  demographics: {len(demographics)}")
    print(f"socioeconomic_facts: {len(socioeconomic_facts)}  mortality_facts: {len(mortality_facts)}")

if __name__ == "__main__":
    main()