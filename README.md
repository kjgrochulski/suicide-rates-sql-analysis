# Global Suicide Rates and Socioeconomic Indicators: SQL Analysis

This project implements a PostgreSQL database and a set of SQL views derived from a public Kaggle dataset. The dataset is a single denormalized CSV that combines WHO suicide rate records (2000-2021) with World Bank GDP and population data. The data are decomposed into a normalized relational schema, and SQL is used to examine temporal trends, the association between GDP and suicide rates, cross-country rankings, and differences by sex and age.

## Core Questions

1. How did national suicide rates change between 2000 and 2021?
2. Is GDP per capita associated with suicide rates within countries over time?
3. Which countries experienced the largest increases and decreases, and which had the highest and lowest rates in the most recent year (2021)?
4. How do male and female rates compare, and how does the comparison vary by age?

## Dataset

[Global Suicide Rates & Socioeconomic Indicators](https://www.kaggle.com/datasets/samartalwar/global-suicide-rates-and-socioeconomic-indicators) (Kaggle, samartalwar), licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

- 18,315 rows, 185 countries, 2000-2021
- Columns: `country`, `country_code`, `year`, `sex`, `age_bracket`, `suicide_rate_per_100k`, `generation`, `gdp_usd`, `gdp_per_capita_usd`, `total_country_population`
- According to the dataset description, the suicide data originate from the WHO and the GDP and population data from the World Bank.
- The dataset description does not state how the rates were calculated (for example, if age-standardized).

The raw CSV is not included in this repo. See [Setup](#setup) for download instructions.

## Tools

- PostgreSQL (official Docker image)
- Python 3 with pandas (data exploration and decomposition of the source CSV)
- `psql` command-line client
- SQL features used: joins, common table expressions (CTEs), window functions (`LAG`, rolling `AVG`), `CORR()`, conditional aggregation (`CASE`, `FILTER`), self-joins, views, composite primary and foreign keys

## Project Structure

```
.
├── data/
│   ├── raw/                 # source CSV (not tracked)
│   └── processed/           # CSVs written by split_tables.py (not tracked)
├── data_exploration.py      # checks run on the raw file before designing the schema
├── split_tables.py          # splits the raw CSV into four table files
├── schema.sql               # CREATE TABLE statements
├── views.sql                # analysis views
├── requirements.txt
├── README.md
├── LICENSE
└── .gitignore

```

## Database Design

The source file is a single flat table. GDP, GDP per capita, and population are repeated on every row for a given country-year, whereas the suicide rate varies by sex and age group within that same country-year. Storing both in one table introduces substantial redundancy in the economic variables.

The file was decomposed so that each value is stored once, at the level of granularity at which it varies:

- `socioeconomic_facts` stores GDP and population once per country-year (4,070 rows, reduced from 18,315).
- `mortality_facts` retains one row per country-year-demographic group (18,315 rows).
- `countries` and `demographics` are dimension (lookup) tables for the repeated country and sex/age values.

```
countries(country_code PK, country)
demographics(demographic_id PK, sex, age_bracket, age_scheme, sex_is_total)
socioeconomic_facts(country_code PK/FK, year PK, gdp_usd, gdp_per_capita_usd, total_country_population)
mortality_facts(country_code PK/FK, year PK/FK, demographic_id PK/FK, suicide_rate_per_100k)
```

`mortality_facts` has a composite foreign key on `(country_code, year)` referencing `socioeconomic_facts`, which guarantees that every mortality record has a corresponding GDP and population record for the same country and year.

### Checks done before designing the schema

Performed in `data_exploration.py`:

- **GDP and population are constant within a country-year.** No country-year contains conflicting values, so retaining a single row per country-year results in no information loss.
- **50 country-years have no GDP data.** They belong to five countries: Cuba (2021), Eritrea (2012-2021), North Korea (2000-2021), South Sudan (2000-2007 and 2016-2021), and Yemen (2019-2021). These rows are retained with null GDP values because the mortality data remain valid. Queries involving GDP exclude the null values.
- **`generation` is functionally dependent on `age_bracket`.** Each bracket maps to exactly one generation, so the column was dropped as redundant.
- **`age_bracket` combines overlapping sets of brackets.** In addition to `all_ages`, it contains a decade set (10-19, 20-29, 30-39, 40-49, 50-59, 60-69, 70plus) and a second set (15-19, 15-29, 30-49, 50-69). Using both together would count individuals more than once. The `age_scheme` column in `demographics` classifies each bracket as `total`, `decade`, or `coarse`, and each analysis uses a single scheme.
- **Age brackets are available for 2021 only.** Every country-year has `all_ages` rates for `both`, `male`, and `female`. Only 2021 also includes the age brackets (555 country-year-sex groups: 185 countries x 3 sex values). The remaining 11,655 groups contain `all_ages` only.
- **The data are rates rather than counts, and population by age or sex group is not provided.** Without those denominators, rates cannot be validly averaged or summed across groups. Country-level totals therefore use the provided `both` / `all_ages` row rather than an aggregation of subgroups.

`sex_is_total` and `age_scheme = 'total'` together identify the `both` / `all_ages` row. Filtering on both conditions returns exactly one row per country-year (4,070 rows), and the trend, correlation, and ranking views rely on this filter.

## Setup

### Prerequisites

- Docker
- Python 3
- `psql` client 

### Steps

Run all commands from the project root.

1. Python environment
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   mkdir -p data/raw data/processed
   ```

2. Download the dataset from Kaggle (linked above) and save as: data/raw/global_suicide_rates_real_who_worldbank.csv

3. Start PostgreSQL in Docker (default credentials, intended for local development only)
   ```bash
   docker run --name suicide-db -e POSTGRES_PASSWORD=postgres -p 5433:5432 -d postgres
   ```

4. Create the database and tables (password: postgres)
   ```bash
   psql -h localhost -p 5433 -U postgres -c "CREATE DATABASE suicide_socioeconomic;"
   psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic -f schema.sql
   ```

5. Split the raw CSV into one file per table
   ```bash
   python split_tables.py
   # Expected output:
   #   countries: 185  demographics: 36
   #   socioeconomic_facts: 4070  mortality_facts: 18315
   ```

6. Load the tables (order matters due to the foreign keys)
   ```bash
   psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic -c "\copy countries FROM 'data/processed/countries.csv' WITH (FORMAT csv, HEADER true)"
   psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic -c "\copy demographics(demographic_id, sex, age_bracket, age_scheme, sex_is_total) FROM 'data/processed/demographics.csv' WITH (FORMAT csv, HEADER true)"
   psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic -c "\copy socioeconomic_facts FROM 'data/processed/socioeconomic_facts.csv' WITH (FORMAT csv, HEADER true)"
   psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic -c "\copy mortality_facts FROM 'data/processed/mortality_facts.csv' WITH (FORMAT csv, HEADER true)"
   # Expected row counts: 185, 36, 4070, 18315
   ```

7. Create the analysis views
   ```bash
   psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic -f views.sql
   ```

To run queries interactively, connect with `psql -h localhost -p 5433 -U postgres -d suicide_socioeconomic`.
Restart with `docker start suicide-db`.

Example:

```sql
SELECT * FROM country_trend WHERE country_code = 'USA' ORDER BY year;
SELECT * FROM female_exceeds_male_2021 ORDER BY male_to_female_ratio;
```

### Verification

After step 7, the following queries should return the values listed below.

```sql
SELECT year, rate FROM country_trend WHERE country_code = 'USA' AND year IN (2000, 2021) ORDER BY year;
SELECT male_rate, female_rate, male_to_female_ratio FROM sex_gap_by_age_2021 WHERE country_code = 'IND' AND age_bracket = '10-19';
SELECT COUNT(*) FROM female_exceeds_male_2021;
```

- `country_trend` for `USA`: 11.17 (2000) and 15.63 (2021)
- `sex_gap_by_age_2021` for India, ages 10-19: male 5.17, female 8.66, ratio 0.60
- `female_exceeds_male_2021`: 21 rows

## Analysis Views

All views are defined in `views.sql`.

| View | Returns |
|---|---|
| `country_trend` | Annual total rate per country, the preceding year's rate, and a trailing 5-year moving average (computed over fewer than 5 years for the first four years) |
| `yoy_changes` | Year-over-year change in the rate and in GDP per capita, per country |
| `gdp_rate_correlation` | Per-country correlation between GDP per capita and the rate (raw levels, 2000-2021; countries with at least 10 years of GDP data) |
| `gdp_rate_correlation_yoy` | Per-country correlation between year-over-year changes in GDP per capita and in the rate (countries with at least 10 changes) |
| `country_rate_change` | Each country's 2000 rate, 2021 rate, and the change between them |
| `sex_gap_2021` | Male rate, female rate, and male-to-female ratio per country, 2021 |
| `sex_gap_by_age_2021` | The same quantities by decade age bracket, 2021 |
| `female_exceeds_male_2021` | Country-age groups in 2021 in which the female rate exceeds the male rate (countries with at least 1 million people and a nonzero male rate) |

## Findings

All rates are suicides per 100,000 people. Country names in the text are common names; the dataset and database use official names (for example, "Korea, Republic of" for South Korea and "Russian Federation" for Russia).

### 1. Trends over time

`country_trend` provides each country's rate by year. In the United States, the rate rose from 11.17 in 2000 to 15.63 in 2021 (approximately +40%), increasing in 17 of the 21 year-over-year comparisons.

### 2. GDP and suicide rate

**First attempt: raw values.** For each country, GDP per capita was correlated with the suicide rate across 2000-2021 (`gdp_rate_correlation`). The coefficients were large, ranging from +0.97 (United States) to -0.98 (Myanmar). However, strong positive and strong negative coefficients both occurred among high- and low-income countries (positive: United States, Djibouti, Philippines; negative: Myanmar, Switzerland, Singapore), so the sign of the coefficient did not track income level. A plausible explanation is that each series tends to move in a single direction over the 22-year period, in which case the correlation of raw levels largely reflects a shared trend. The second analysis tests this explanation.

**Second attempt: year-over-year changes.** Correlating year-over-year changes (first differences) in GDP per capita with those in the suicide rate removes the shared trend (`gdp_rate_correlation_yoy`). The coefficients were substantially smaller. The largest were +0.56 (Nepal) and -0.52 (Montenegro), and the coefficient for Myanmar dropped from -0.98 to -0.43.

**Result:** Within countries, GDP per capita and suicide rates show at most a moderate association once the shared trend is removed. Each country contributes at most 21 observations, no significance tests were performed, and the correlation does not establish causation.

### 3. Rankings, 2000 to 2021

`country_rate_change` compares each country's 2021 rate with its 2000 rate.

Largest increases:

| Country | 2000 | 2021 | Change |
|---|---|---|---|
| Lesotho | 12.68 | 28.66 | +15.98 |
| Eswatini | 12.53 | 27.23 | +14.70 |
| South Korea | 15.06 | 27.53 | +12.47 |
| South Africa | 13.13 | 22.30 | +9.17 |
| Uruguay | 16.35 | 24.75 | +8.40 |

Largest decreases:

| Country | 2000 | 2021 | Change |
|---|---|---|---|
| Russia | 53.06 | 21.37 | -31.69 |
| Lithuania | 50.40 | 22.12 | -28.28 |
| Sri Lanka | 38.90 | 14.74 | -24.16 |
| Belarus | 39.50 | 15.61 | -23.89 |
| Latvia | 34.82 | 15.21 | -19.61 |

Nine of the ten largest decreases occurred in Eastern or Central European countries or in former Soviet states (the exception is Sri Lanka). The dataset contains no variables that would account for this pattern.

Highest 2021 rates: Lesotho (28.66), South Korea (27.53), Eswatini (27.23), Guyana (24.78), Uruguay (24.75).

Lowest 2021 rates: Saint Vincent and the Grenadines (0.41), Syria (0.59), Jordan (0.60), Egypt (0.63), Palestine (0.65). Seven of the ten lowest are in the Middle East or North Africa. These are reported rates, and reporting practices differ greatly between countries, so a low reported rate does not necessarily indicate a low actual rate.

`country_rate_change` also includes a percent-change column. Countries were not ranked by it, because countries with very low initial rates show large percentage changes from small absolute changes.

### 4. Male and female rates, 2021

`sex_gap_2021` gives the male rate, female rate, and male-to-female ratio for each country.

In 2021, the male rate exceeds the female rate in every country for which the ratio could be calculated (both rates available and a nonzero female rate). Saint Vincent and the Grenadines has a female rate of 0.0, so no ratio is defined for it.

Highest male-to-female ratios: Kuwait (10.53), Brunei (8.51), Qatar (8.10), Venezuela (7.61), Georgia (7.33). Kuwait's rates are 3.58 (male) and 0.34 (female). Several of these countries are small in population or have very low female rates, so the ratio is sensitive to small changes in the underlying rate.

Lowest ratios: India (1.23), Antigua and Barbuda (1.29), North Korea (1.30), China (1.37), Albania (1.37). As noted above, these are reported rates, and the dataset cannot separate differences in reporting from differences in actual underlying rates.

### 5. India and China by age, 2021

India and China, the two most populous countries, both have low ratios in the sex comparison above (India's is the lowest). `sex_gap_by_age_2021` shows that the two countries arrive at these ratios through different age-specific patterns.

| Age | India male | India female | India ratio | China male | China female | China ratio |
|---|---|---|---|---|---|---|
| 10-19 | 5.17 | 8.66 | 0.60 | 1.87 | 1.46 | 1.28 |
| 20-29 | 18.47 | 18.03 | 1.02 | 6.31 | 3.14 | 2.01 |
| 30-39 | 19.48 | 14.03 | 1.39 | 7.03 | 3.71 | 1.89 |
| 40-49 | 19.63 | 10.84 | 1.81 | 8.86 | 5.35 | 1.66 |
| 50-59 | 21.81 | 14.07 | 1.55 | 11.90 | 8.75 | 1.36 |
| 60-69 | 19.26 | 14.56 | 1.32 | 17.43 | 12.88 | 1.35 |
| 70plus | 27.09 | 18.03 | 1.50 | 48.21 | 30.85 | 1.56 |

- **India:** The female rate exceeds the male rate at ages 10-19 and is approximately equal at 20-29. The ratio is highest at 40-49.
- **China:** The male rate exceeds the female rate in every age bracket. The ratio is highest at 20-29 (2.01).

Published studies of India report female suicide rates equal to or above male rates under age 30 (Patel et al., 2012; the systematic review and Vijayakumar, listed below) and describe pressures on young married women. Earlier studies of China attributed its low overall ratio to young rural women (Yip and Liu, 2006). These studies cover earlier periods than this dataset, and the dataset has no rural/urban breakdown, so it cannot explain why China's 2021 pattern differs from the earlier findings.

### 6. Is the higher female rate at ages 10-19 specific to India?

No. Higher female rates are concentrated in ages 10-19. `female_exceeds_male_2021` includes only countries with at least 1 million people and a nonzero male rate. Results by age bracket:

| Age | Female rate above male | Countries compared | Share |
|---|---|---|---|
| 10-19 | 18 | 158 | 11.4% |
| 20-29 | 1 | 158 | 0.6% |
| 30-39 | 0 | 158 | 0.0% |
| 40-49 | 0 | 157 | 0.0% |
| 50-59 | 1 | 158 | 0.6% |
| 60-69 | 0 | 158 | 0.0% |
| 70plus | 1 | 158 | 0.6% |

In the other six brackets combined, 3 of 947 comparisons (0.3%) show a higher female rate, and all three are near parity (ratio 0.93 or higher): Haiti at 20-29, Afghanistan at 50-59, and Saudi Arabia at 70plus.

The 18 countries with a higher female rate at ages 10-19:

| Country | Male | Female | Ratio |
|---|---|---|---|
| North Macedonia | 0.80 | 2.04 | 0.39 |
| Haiti | 2.41 | 4.26 | 0.57 |
| India | 5.17 | 8.66 | 0.60 |
| Bolivia | 1.50 | 2.38 | 0.63 |
| Greece | 0.37 | 0.58 | 0.64 |
| Estonia | 4.96 | 7.11 | 0.70 |
| Papua New Guinea | 1.09 | 1.52 | 0.72 |
| Nicaragua | 2.75 | 3.41 | 0.81 |
| Uzbekistan | 9.23 | 11.32 | 0.82 |
| Albania | 1.05 | 1.28 | 0.82 |
| Bulgaria | 1.10 | 1.30 | 0.85 |
| Peru | 1.32 | 1.53 | 0.86 |
| Mauritius | 6.48 | 7.16 | 0.91 |
| Paraguay | 7.97 | 8.71 | 0.92 |
| Bangladesh | 2.84 | 3.06 | 0.93 |
| New Zealand | 5.97 | 6.34 | 0.94 |
| Sudan | 2.57 | 2.60 | 0.99 |
| Lebanon | 0.72 | 0.73 | 0.99 |

These countries are distributed across Latin America, Eastern Europe, South Asia, Africa, the Pacific, and the Middle East, and include several high-income countries (Greece, New Zealand, Estonia). The list shows no obvious regional or income pattern.

Adolescent rates are low, so many of these ratios are close to 1 and can shift considerably with a small number of deaths. Individual countries should therefore be interpreted cautiously; the finding that warrants attention is the concentration in a single age bracket, not any one country. India stands out in this sense because its rates are high and its population is large. The dataset contains no counts or confidence intervals and does not explain why the female rate approaches or exceeds the male rate at these ages.

Roughly 1,100 age-specific comparisons were made, so some ratios below 1 are expected from random variation in small counts, particularly where the true ratio is near 1. The contrast between the 10-19 bracket (11.4%) and the other brackets (0.3%) is the more informative result.

## Limitations

- **Rates only.** The dataset contains no death counts and no population by sex or age group, so rates cannot be combined across groups and no confidence intervals can be computed.
- **Age brackets cover 2021 only.** Male, female, and both-sex totals exist for every year, but the age breakdown exists only for 2021.
- **Missing GDP.** 50 country-years in five countries have no GDP data (see Database Design).
- **Reporting differs by country.** Rankings compare reported rates. Differences in how countries record and classify suicides are likely influenced by a range of factors that lie beyond the scope of the dataset.
- **Source not verified.** The data come pre-merged from Kaggle. They were not compared with the original WHO or World Bank data, and the dataset description does not state how the rates were calculated. Figures from published studies are not directly comparable to this dataset because they differ in age range, year, and estimation method.
- **Correlation analysis.** Each country contributes at most 21 year-over-year observations, no significance testing was performed, and correlation does not establish causation.
- **Thresholds are judgment-based.** The 1 million population cutoff and the nonzero male rate filter in the age comparison were chosen to reduce small-number artifacts and were not derived from a statistical test. The cutoff applies to total national population, not to the population of each age group. A male rate of exactly zero may reflect no deaths or missing data; the dataset does not distinguish the two.

## Possible Extensions

- Calculate the male-to-female ratio for every year (2000-2021) to examine how the sex gap changes over time, including for India and China.
- Add World Bank income groups or regions as a table to enable comparisons between groups of countries.
- Test the correlations for statistical significance.

## References

- Patel V, et al. [Suicide mortality in India: a nationally representative survey](https://researchonline.lshtm.ac.uk/id/eprint/24811). The Lancet, 2012.
- Vijayakumar L. [Suicide in women](https://pmc.ncbi.nlm.nih.gov/articles/PMC4539867).
- [Suicide in India: a systematic review](https://pmc.ncbi.nlm.nih.gov/articles/PMC4120287).
- Yip PSF, Liu KY. [The ecological fallacy and the gender ratio of suicide in China](https://www.cambridge.org/core/product/72F0B482E3D390B0D3500BBD34572C1C/core-reader). 2006.

## License

The code in this repository (SQL and Python) is released under the [MIT License](LICENSE). The source dataset is licensed separately by its author under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) and is not redistributed here. Figures and tables in this README that are derived from the dataset are attributed to it under that license.

## Author

Karol Grochulski, University of Pittsburgh, B.S. Data Science
[GitHub](https://github.com/kjgrochulski) | [LinkedIn](https://www.linkedin.com/in/karol-grochulski-6332a3351)