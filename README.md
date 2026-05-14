# 🧠 AI-Powered Customer Feedback Intelligence System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-BigQuery_%7C_Vertex_AI-blue.svg)](https://cloud.google.com/)

## 📌 Project Overview
This end-to-end data engineering and AI project ingests unstructured customer feedback from multiple channels (product reviews, support tickets, social media) into a SQL database. It leverages Large Language Models (LLMs) via Google Cloud's Vertex AI to categorize sentiment, extract topics, and score feedback [3]. The structured insights can then be surfaced via a BI dashboard (e.g., Power BI or Tableau) to enable product teams to act on feedback in near real-time [5].

## 🏗 Architecture & Tech Stack
* **Storage & Compute**: Google BigQuery (EDW) [4]
* **AI/ML Processing**: BigQuery ML, Vertex AI (Gemini Pro), Cloud Natural Language API [6-8]
* **Data Sources**: E-commerce Reviews, IT Support Tickets [5, 9]
* **Visualization**: Power BI / Tableau [4]

## 📁 Repository Structure
```text
customer-feedback-ai/
├── README.md                  <- Project documentation [10]
├── data/
│   └── sample_feedback.csv    <- 50-row sample to test pipeline [11]
├── sql/  
│   ├── 01_setup_schema.sql    <- Create datasets, tables, and AI models [11]
│   ├── 02_ai_analytics.sql    <- AI processing queries (Sentiment & Topics) [11]
├── dashboards/
│   └── feedback_insights.pbix <- Exported Power BI dashboard file [12]
📦 Dataset Content
This project utilizes publicly available Kaggle datasets to simulate a real-world omnichannel support environment
:
E-Commerce 100k Reviews: Product sentiment and topic labeling
.
Customer Support Tickets: Support ticket ingestion and priority classification
.
⚙️ Installation and Setup
Configure Google Cloud: Ensure you have a GCP project with billing enabled and the BigQuery and Vertex AI APIs turned on
.
Set up a Cloud Resource Connection: Create a connection in BigQuery (e.g., us.example_connection) and grant the Vertex AI User role to the generated service account
.
Execute SQL: Run the scripts located in the sql/ folder in your BigQuery console to create the tables, remote models, and generate insights.
🚀 Results and Evaluation
By transitioning from manual feedback review to this automated pipeline, we successfully categorized raw text using BigQuery's AI.CLASSIFY and ML.GENERATE_TEXT functions. The results highlight key product pain points, urgent support issues, and overall brand sentiment
.
📝 License
This project is licensed under the MIT License
.

***
