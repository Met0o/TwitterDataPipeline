
###############################################################################################
############## Step 1: Creating a Database and Table to Store the Twitter Data ################ 
###############################################################################################

## Building a pipeline to store Tweets as we stream them over time. 
## To start, we are going to create SQLite database using R:

# First, installing required packages
install.packages("RSQLite")
install.packages("rtweet")
install.packages("tm")
install.packages("dplyr")
install.packages("knitr")
install.packages("wordcloud")
install.packages("lubridate")
install.packages("ggplot2")
install.packages("wordcloud2")
install.packages("SnowballC")
install.packages("SentimentAnalysis")
install.packages("tidytext")
install.packages("textdata")
install.packages("stringr")
install.packages("syuzhet")
install.packages("purrr")
install.packages("quanteda")

# Second, importing necessary libraries and functions
library(RSQLite)
library(rtweet)
library(tm)
library(dplyr)
library(knitr)
library(wordcloud)
library(lubridate)
library(ggplot2)
library(wordcloud2)
library(SnowballC)
library(SentimentAnalysis)
library(tidytext)
library(textdata)
library(stringr)
library(syuzhet)
library(purrr)
library(quanteda)
# source("transform_and_clean_tweets.R")

# Creating the SQLite database
conn <- dbConnect(RSQLite::SQLite(), "Tweet_DB.db")

# Create a table inside the database to hold the tweets. 
# In this case, we are going to store the following variables:
# Tweet_ID as an INTEGER primary key
# User as TEXT
# Tweet_Content as TEXT
# Date_Created as INTEGER
# Setting dates as integers because SQLite doesn't have a reserved data type for dates and times. 
# Dates will be stored as the number of seconds since 1970-01-01.

dbExecute(conn, "CREATE TABLE Tweet_Data(
          Tweet_ID INTEGER PRIMARY KEY,
          User TEXT,
          Tweet_Content TEXT,
          Date_Created INTEGER)")

# Once you have created the table, you can go to sqlite3.exe and check that 
# is has indeed been created. Use the following SQL code to confirm:

## .open Tweet_DB.db
## .tables
## .schema Tweet_Data

# Result should be like this

## CREATE TABLE Tweet_Data(
##  Tweet_ID INTEGER PRIMARY KEY,
##  User TEXT,
##  Tweet_Content TEXT,
##  Date_Created INTEGER);

###############################################################################################
###################### Step 2 Stream Tweets About your Favourite Topics ####################### 
###############################################################################################

# The process of setting up our Twitter listener. 
# The first thing that you will need is to import the rtweet package and input your 
# application's access tokens and secrets as described in the beginning:

token <- create_token(app = 'DataPipelineByMeto',
                      consumer_key = 'KEY_HERE',
                      consumer_secret = 'KEY_HERE',
                      access_token = 'KEY_HERE',
                      access_secret = 'KEY_HERE')

# stream tweets containing hashtags related to DataScience

keys <- "#nlp,#machinelearning,#datascience,#chatbots,#naturallanguageprocessing,#deeplearning"
## Alternative research 
keys <- "#Syria,#Turkey"

# with the keywords defined, it is time to define the tweet streaming loop. 

# Initialize the streaming hour tally
hour_counter <- 0

################################################################################################
# Defining the transform_and_clean_tweets function that removes retweets if desired, 
# selects the columns we want to keep from all those given by the Twitter API, 
# and normalizes the text contained in the Tweets.
# ##############################################################################################

transform_and_clean_tweets <- function(filename, remove_rts = TRUE){
  
  # Import the normalize_text function
  source("normalize_text.R")
  
  # Parse the .json file given by the Twitter API into an R data frame
  df <- parse_stream(filename)
  # If remove_rst = TRUE, filter out all the retweets from the stream
  if(remove_rts == TRUE){
    df <- filter(df,df$is_retweet == FALSE)
  }
  # Keep only the tweets that are in English
  df <- filter(df, df$lang == "en")
  # Select the features that you want to keep from the Twitter stream and rename them
  # so the names match those of the columns in the Tweet_Data table in our database
  small_df <- df[,c("screen_name","text","created_at")]
  names(small_df) <- c("User","Tweet_Content","Date_Created")
  # Finally normalize the tweet text
  small_df$Tweet_Content <- sapply(small_df$Tweet_Content, normalize_text)
  # Return the processed data frame
  return(small_df)
}

################################################################################################
# Initialize a while loop that stops when the number of hours you want                       ###
# to stream tweets for is exceeded.                                                          ###
#                                                                                            ###
# That loop streams as many tweets as possible mentioning any of the hashtags in the key     ###
# strings in intervals of 2 hours for a total time of 12 hours. Every 2 hours, the Twitter   ###
# listener creates a .json file in your current working directory                            ###
################################################################################################

while(hour_counter <= 2){
  # Set the stream time to 2 hours each iteration (7200 seconds)
  streamtime <- 7200
  # Create the file name where the 2 hour stream will be stored. 
  # Note that the Twitter API outputs a .json file.
  filename <- paste0("nlp_stream_",format(Sys.time(),'%d_%m_%Y__%H_%M_%S'),".json")
  # Stream Tweets containing the desired keys for the specified amount of time
  stream_tweets(q = keys, timeout = streamtime, file_name = filename)
  # Clean the streamed tweets and select the desired fields
  clean_stream <- transform_and_clean_tweets(filename, remove_rts = TRUE)
  # Append the streamed tweets to the Tweet_Data table in the SQLite database
  dbWriteTable(conn, "Tweet_Data", clean_stream, append = T)
  # Delete the .json file from this 2-hour stream
  file.remove(filename)
  # Add the hours to the tally
  hour_counter <- hour_counter + 2
}

#######################################################################
##                   Normalizing the data                            ##
#######################################################################

normalize_text <- function(text){
  # Keep only ASCII characters
  text = iconv(text, "latin1", "ASCII", sub="")
  # Convert to lower case characters
  text = tolower(text)
  # Remove any HTML tags
  text = gsub("<.*?>", " ", text)
  # Remove URLs
  text = gsub("\\s?(f|ht)(tp)(s?)(://)([^\\.]*)[\\.|/](\\S*)", "", text)
  # Keep letters and numbers only
  text = gsub("[^[:alnum:]]", " ", text)
  # Remove stop words
  text = removeWords(text,c("rt","gt",stopwords("en")))
  # Remove any extra white space
  text = stripWhitespace(text)                                 
  text = gsub("^\\s+|\\s+$", "", text)                         
  
  return(text)
}

#######################################################################
# After these steps, the resulting state is a SQLite database 
# populated with all the streamed tweets. Sample queries to validate 
# that everything worked correctly:
#######################################################################

data_test <- dbGetQuery(conn, "SELECT * FROM Tweet_Data LIMIT 20")
unique_rows <- dbGetQuery(conn, "SELECT COUNT() AS Total FROM Tweet_Data")
kable(data_test)

# Get total number of rows in the DB

print(as.numeric(unique_rows))

#######################################################################
####################### Step 3 Analyze ################################
#######################################################################

# Building a nice wordcloud to visualize the data:

# Gather all tweets from the database
all_tweets <- dbGetQuery(conn, "SELECT Tweet_ID, Tweet_Content FROM Tweet_Data")

# Create a term-document matrix and sort the words by frequency
dtm <- TermDocumentMatrix(VCorpus(VectorSource(all_tweets$Tweet_Content)))
dtm_mat <- as.matrix(dtm)
sorted <- sort(rowSums(dtm_mat), decreasing = TRUE)
freq_df <- data.frame(words = names(sorted), freq = sorted)

# Plot the wordcloud
set.seed(1234)
wordcloud(words = freq_df$words, freq = freq_df$freq, min.freq = 10,
          max.words=500, random.order=FALSE, rot.per=0.15,
          colors=brewer.pal(8, "RdYlGn"))

# Plot usuing wordcloud2
wordcloud2(freq_df, size = 0.7, shape = 'cardioid')

######################################################################## 
#####################      Sentiment Analysis      #####################
######################################################################## 

Visualize and Plot the Sentiment using the Syuzhet library

# “syuzhet” uses NRC Emotion lexicon. The NRC emotion lexicon is a list of words and their associations 
# with eight emotions (anger, fear, anticipation, trust, surprise, sadness, joy, and disgust) and two 
# sentiments (negative and positive). 

# The get_nrc_sentiment function returns a data frame in which each row represents a sentence from 
# the original file. The columns include one for each emotion type was well as the positive or negative 
# sentiment valence. It allows us to take a body of text and return which emotions it represents — 
# and also whether the emotion is positive or negative. 

library(RSQLite)
library(tm)
library(ggplot2)
library(wordcloud2)
library(syuzhet)

# Creating the SQLite database
conn <- dbConnect(RSQLite::SQLite(), "Tweet_DB.db")

## Extracting the data from SQL
Tweets <- dbGetQuery(conn, "SELECT Tweet_Content FROM Tweet_Data")

## Checking the structure of the DF
head(Tweets$Tweet_Content)

# Converting the DF to matrix for vectorization
TweetsMatrix <- as.matrix(Tweets)

d <- get_nrc_sentiment(TweetsMatrix)
td <- data.frame(t(d))

## The function rowSums computes column sums across rows for each level of a grouping variable
td_new <- data.frame(rowSums(td[10:23725]))

## Transformation and cleaning
names(td_new)[1] <- "count"
td_new <- cbind("sentiment" = rownames(td_new), td_new)
rownames(td_new) <- NULL
td_new2<-td_new[1:10,]

###############################################################################################
############################            Step 5 N-Grams            ############################# 
###############################################################################################

## By using “quanteda” we can compute tri-grams and find commonly occuring sequences of 3 words.
library(tm)
library(RSQLite)
library(quanteda)

# Get all the Tweets
TweetsNgrams <- dbGetQuery(conn, "SELECT Tweet_Content FROM Tweet_Data")

# Removing stopwords from the collocations so we can get a full view of 
# which are the most frequently used collection of three words all of the tweets. 
collocations(TweetsNgrams, size = 2:3)
print(removeFeatures(collocations(TweetsNgrams, size = 2:3), stopwords("english")))


