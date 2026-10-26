import pandas as pd
df = pd.read_csv("data/raw/global_suicide_rates_real_who_worldbank.csv")

print(df.shape)
print(df.head())

#   grain mismatch
print(df.columns.tolist())
print(df.dtypes)

#   redundancy
print(df.groupby("age_bracket")["generation"].nunique())

#   grain
grain_check = df.groupby(["country_code", "year"])[["gdp_usd", "gdp_per_capita_usd", "total_country_population"]].nunique()
print(grain_check.value_counts())

#   double counting 
print(df.groupby(["country_code", "year", "sex"])["age_bracket"].apply(list).iloc[0])


grain = df.groupby(["country_code", "year"])[["gdp_usd", "gdp_per_capita_usd", "total_country_population"]].nunique()
missing_gdp = grain[grain["gdp_usd"] == 0]
print(missing_gdp.index.tolist())


bracket_sets = df.groupby(["country_code", "year", "sex"])["age_bracket"].apply(lambda x: tuple(sorted(set(x))))
print(bracket_sets.value_counts())

print(df["sex"].unique())

detailed = df[df["age_bracket"] != "all_ages"][["country_code", "year"]].drop_duplicates()
print(detailed["year"].value_counts())

