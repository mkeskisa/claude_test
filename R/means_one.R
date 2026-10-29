library(tidyverse)


mtcars %>% 
  select(where(is.numeric)) %>% 
  group_by(cyl) %>% 
  summarise(across(everything(), list(mean = mean, median = median))) %>%
  pivot_longer(cols = -cyl, names_to = "metric", values_to = "value")
