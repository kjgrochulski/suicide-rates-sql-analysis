CREATE OR REPLACE VIEW country_trend AS
SELECT
    m.country_code,
    c.country,
    m.year,
    m.suicide_rate_per_100k AS rate,
    LAG(m.suicide_rate_per_100k) OVER (PARTITION BY m.country_code ORDER BY m.year) AS prev_year_rate,
    ROUND(
        AVG(m.suicide_rate_per_100k) OVER (
            PARTITION BY m.country_code ORDER BY m.year
            ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
        ), 2
    ) AS rolling_5yr_avg
FROM mortality_facts m
JOIN demographics d ON m.demographic_id = d.demographic_id
JOIN countries c ON m.country_code = c.country_code
WHERE d.sex_is_total AND d.age_scheme = 'total';



CREATE OR REPLACE VIEW yoy_changes AS
SELECT
    m.country_code,
    m.year,
    m.suicide_rate_per_100k - LAG(m.suicide_rate_per_100k) OVER (PARTITION BY m.country_code ORDER BY m.year) AS rate_change,
    s.gdp_per_capita_usd - LAG(s.gdp_per_capita_usd) OVER (PARTITION BY m.country_code ORDER BY m.year) AS gdp_change
FROM mortality_facts m
JOIN demographics d ON m.demographic_id = d.demographic_id
JOIN socioeconomic_facts s ON m.country_code = s.country_code AND m.year = s.year
WHERE d.sex_is_total AND d.age_scheme = 'total';



CREATE OR REPLACE VIEW gdp_rate_correlation_yoy AS
SELECT
    country_code,
    CORR(gdp_change, rate_change) AS yoy_correlation,
    COUNT(*) AS n
FROM yoy_changes
WHERE gdp_change IS NOT NULL AND rate_change IS NOT NULL
GROUP BY country_code
HAVING COUNT(*) >= 10;

CREATE OR REPLACE VIEW gdp_rate_correlation AS
SELECT
    m.country_code,
    c.country,
    CORR(s.gdp_per_capita_usd, m.suicide_rate_per_100k) AS correlation,
    COUNT(*) AS years_of_data
FROM mortality_facts m
JOIN demographics d ON m.demographic_id = d.demographic_id
JOIN countries c ON m.country_code = c.country_code
JOIN socioeconomic_facts s ON m.country_code = s.country_code AND m.year = s.year
WHERE d.sex_is_total AND d.age_scheme = 'total'
    AND s.gdp_per_capita_usd IS NOT NULL
GROUP BY m.country_code, c.country
HAVING COUNT(*) >= 10;


CREATE OR REPLACE VIEW country_rate_change AS
SELECT
    curr.country_code,
    curr.country,
    start.rate AS rate_2000,
    curr.rate AS rate_2021,
    ROUND(curr.rate - start.rate, 2) AS absolute_change,
    ROUND(((curr.rate - start.rate) / NULLIF(start.rate, 0)) * 100, 1) AS pct_change
FROM country_trend curr
JOIN country_trend start
    ON curr.country_code = start.country_code AND start.year = 2000
WHERE curr.year = 2021;


CREATE OR REPLACE VIEW sex_gap_2021 AS
SELECT
    m.country_code,
    c.country,
    MAX(CASE WHEN d.sex = 'male' THEN m.suicide_rate_per_100k END) AS male_rate,
    MAX(CASE WHEN d.sex = 'female' THEN m.suicide_rate_per_100k END) AS female_rate,
    ROUND(
        MAX(CASE WHEN d.sex = 'male' THEN m.suicide_rate_per_100k END)
        / NULLIF(MAX(CASE WHEN d.sex = 'female' THEN m.suicide_rate_per_100k END), 0),
        2
    ) AS male_to_female_ratio
FROM mortality_facts m
JOIN demographics d ON m.demographic_id = d.demographic_id
JOIN countries c ON m.country_code = c.country_code
WHERE d.age_scheme = 'total' AND m.year = 2021 AND d.sex IN ('male', 'female')
GROUP BY m.country_code, c.country;


CREATE OR REPLACE VIEW sex_gap_by_age_2021 AS
WITH by_sex AS (
    SELECT
        m.country_code,
        c.country,
        d.age_bracket,
        MAX(CASE WHEN d.sex = 'male'   THEN m.suicide_rate_per_100k END) AS male_rate,
        MAX(CASE WHEN d.sex = 'female' THEN m.suicide_rate_per_100k END) AS female_rate
    FROM mortality_facts m
    JOIN demographics d ON m.demographic_id = d.demographic_id
    JOIN countries c ON m.country_code = c.country_code
    WHERE m.year = 2021
      AND d.age_scheme = 'decade'
      AND d.sex IN ('male', 'female')
    GROUP BY m.country_code, c.country, d.age_bracket
)
SELECT
    country_code,
    country,
    age_bracket,
    male_rate,
    female_rate,
    ROUND(male_rate / NULLIF(female_rate, 0), 2) AS male_to_female_ratio
FROM by_sex;


-- Country-age groups where the female rate exceeds the male rate (2021).
-- Excludes male_rate = 0 and countries under 1M pop.
CREATE OR REPLACE VIEW female_exceeds_male_2021 AS
SELECT
    g.country_code,
    g.country,
    g.age_bracket,
    g.male_rate,
    g.female_rate,
    g.male_to_female_ratio,
    s.total_country_population
FROM sex_gap_by_age_2021 g
JOIN socioeconomic_facts s
    ON g.country_code = s.country_code AND s.year = 2021
WHERE g.male_to_female_ratio < 1
  AND g.male_rate > 0
  AND s.total_country_population >= 1000000;