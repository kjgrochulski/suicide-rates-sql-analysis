CREATE TABLE countries (
    country_code CHAR(3) PRIMARY KEY,
    country TEXT NOT NULL
);

CREATE TABLE demographics (
    demographic_id SERIAL PRIMARY KEY,
    sex TEXT NOT NULL,
    age_bracket TEXT NOT NULL,
    age_scheme TEXT NOT NULL,
    sex_is_total BOOLEAN NOT NULL,
    UNIQUE (sex, age_bracket)
);

CREATE TABLE socioeconomic_facts (
    country_code CHAR(3) REFERENCES countries(country_code),
    year INT NOT NULL,
    gdp_usd NUMERIC,
    gdp_per_capita_usd NUMERIC,
    total_country_population BIGINT,
    PRIMARY KEY (country_code, year)
);

CREATE TABLE mortality_facts (
    country_code CHAR(3) REFERENCES countries(country_code),
    year INT NOT NULL,
    demographic_id INT REFERENCES demographics(demographic_id),
    suicide_rate_per_100k NUMERIC,
    PRIMARY KEY (country_code, year, demographic_id),
    FOREIGN KEY (country_code, year) REFERENCES socioeconomic_facts(country_code, year)
);
