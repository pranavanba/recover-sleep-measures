source("scripts/etl/fetch-data.R")

fitbit_sleeplogs <- 
  arrow::open_dataset(
    s3$path(stringr::str_subset(dataset_paths, "sleeplogs$"))
  )

vars <- 
  c("ParticipantIdentifier", 
    "LogId",
    "IsMainSleep",
    "StartDate", # YYYY-MM-DDTHH:MM:SS format
    "EndDate" # YYYY-MM-DDTHH:MM:SS format
  )

# Load desired subset of the data in memory and do some feature engineering
sleeplogs_df <- 
  fitbit_sleeplogs %>% 
  select(all_of(c(vars))) %>% 
  collect() %>% 
  distinct() %>% 
  mutate(
    Date = lubridate::as_date(StartDate), # YYYY-MM-DD format
    IsMainSleep = as.logical(IsMainSleep),
    SleepStartTime = lubridate::as_datetime(ifelse(IsMainSleep==TRUE, StartDate, NA)),
    SleepStartTime = ((format(SleepStartTime, format = "%H:%M:%S") %>% lubridate::hms()) / lubridate::hours(24))*24,
    SleepEndTime = lubridate::as_datetime(ifelse(IsMainSleep==TRUE, EndDate, NA)),
    SleepEndTime = ((format(SleepEndTime, format = "%H:%M:%S") %>% lubridate::hms()) / lubridate::hours(24))*24,
    Between8and2 = if_else(SleepStartTime >= 20 | SleepStartTime <= 2, TRUE, FALSE)
  ) %>% 
  filter(IsMainSleep==TRUE)

# Weekly statistics
weekly_stats <- 
  sleeplogs_df %>%
  group_by(ParticipantIdentifier, Week = floor_date(Date, "week")) %>%
  drop_na() %>% 
  summarise(
    across(.cols = all_of(c("Between8and2")),
           .fns = 
             list(
               PercentOfTime = ~sum(.x, na.rm = TRUE)/sum(!is.na(.x)),
               Count = ~sum(!is.na(.x))
             ),
           .names = "{.fn}"),
    .groups = "drop"
  ) %>% 
  ungroup()

# All-time statistics
alltime_stats <- 
  sleeplogs_df %>%
  group_by(ParticipantIdentifier) %>%
  drop_na() %>% 
  summarise(
    across(.cols = all_of(c("Between8and2")),
           .fns = 
             list(
               PercentOfTime = ~sum(.x, na.rm = TRUE)/sum(!is.na(.x)),
               Count = ~sum(!is.na(.x))
             ),
           .names = "{.fn}"),
    .groups = "drop"
  ) %>% 
  ungroup()
