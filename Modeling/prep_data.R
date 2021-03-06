library(DBI)
library(RPostgres)
library(tidyverse)
library(magrittr)
library(lubridate)


# This file cleans brand, size, and subcategory info to get ready to fit.

# Preliminaries
setwd("C:/Users/maran/Documents/Data Projects/Web Scraping/Scraped datasets")
rm(list = ls())
gc()


# Connect to database
db <- "poshmark" # provide the name of your db
host_db <- "localhost" # i.e. # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
db_port <- "5432" # or any other port specified by the DBA
db_user <- "postgres"
db_password <- "Poshmark"

con <- dbConnect(RPostgres::Postgres(), dbname = db, host = host_db, port = db_port, user = db_user, password = db_password)



# Load data
dbSendQuery(con, "SELECT SETSEED(0.5)")
posh_sales <- dbGetQuery(con, "SELECT * FROM solds WHERE RANDOM() <= .2")
posh_sales %<>% filter(date_sold >= "2020-05-01")




# Gentle cleaning of brand and size information
clean_attributes <- function(vector){
  clean_vector <- vector %>% 
    str_remove_all("[[:punct:]]") %>%
    str_replace_all("[[:space:]]", "_") %>%
    tolower
  return(clean_vector)
}

posh_sales %<>% mutate(brand = clean_attributes(brand),
                       size = clean_attributes(size))

# Reduce number of unique categories - we only consider categories that have at least X sales in data
# Other categories will be assigned a label

reduce_attributes <- function(data, sale_cutoff, attribute, 
                              infreq_label = paste("Nonstandard", attribute), 
                              no_label = paste("No", attribute), strip_punct = T){
  
  # Count number of observations within each attribute
  cats <- data %>% 
    group_by(get(attribute)) %>% 
    summarize(count = n()) %>%
    arrange(-count)
  
  names(cats)[1] <- attribute
  
  # Identify small and large brands
  small_cats <- cats %>% 
    filter(count <= sale_cutoff) %>% 
    pull(get(attribute))
  
  large_cats <- cats %>% 
    filter(count > sale_cutoff) %>% 
    filter(!is.na(get(attribute))) %>%
    pull(get(attribute))
  
  # Create new column brand_mod that has the brand if it is a large brand, or contains values for small or no brand
  data %<>% 
    mutate(attr_mod = if_else(get(attribute) %in% small_cats, infreq_label, get(attribute))) %>%
    mutate(attr_mod = if_else(is.na(get(attribute)), no_label, attr_mod))
  
  names(data)[names(data) == "attr_mod"] <- paste0(attribute, "_mod")
  
  # Output list
  outputs <- list(
    data,
    cats,
    small_cats,
    large_cats
  )
  
  return(outputs)
  
}



reduce_brand_list <- reduce_attributes(posh_sales, sale_cutoff = 50, attribute = "brand")
posh_sales <- reduce_brand_list[[1]]
brands     <- reduce_brand_list[[2]]

reduce_size_list <- reduce_attributes(posh_sales, sale_cutoff = 50, attribute = "size")
posh_sales <- reduce_size_list[[1]]
sizes      <- reduce_size_list[[2]]



# Reassign NA's in subcategory into None vs Not Available
posh_sales_subcategories <- posh_sales %>%
  group_by(mkt_cat, subcategory) %>% 
  summarize(count = n()) %>%
  group_by(mkt_cat) %>% 
  summarize(count = n())

with_subs <- posh_sales_subcategories %>% filter(count > 1) %>% pull(mkt_cat)
no_subs   <- posh_sales_subcategories %>% filter(count == 1) %>% pull(mkt_cat)

# Apply to sales data
posh_sales %<>% mutate(subcategory = if_else(is.na(subcategory) & mkt_cat %in% with_subs, 
                                             "None",
                                             if_else(is.na(subcategory) & mkt_cat %in% no_subs, 
                                                     "Not Available", 
                                                     subcategory)))


# identify month sold
posh_sales %<>% mutate(month_sold = as.character(month(date_sold)),
                       super_category = paste(market, category, subcategory, sep = "_"))



gc()
saveRDS(posh_sales, file = "./modeling/ready_data_2020-11.RDS")



