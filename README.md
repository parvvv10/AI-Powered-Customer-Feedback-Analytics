# 🧠 AI-Powered Customer Feedback Intelligence System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-BigQuery_%7C_Vertex_AI-blue.svg)](https://cloud.google.com/)

## 📌 Project Overview
This end-to-end data engineering and analytics project ingests unstructured customer feedback from multiple channels (product reviews, support tickets, and social media) into a cloud data warehouse. I[...]

## 🏗 Architecture & Tech Stack
* **Storage & Compute**: Google BigQuery (EDW)
* **AI/ML Processing**: BigQuery ML, Vertex AI (Gemini Pro), Cloud Natural Language API
* **Data Sources**: E-commerce Reviews, IT Support Tickets
* **Visualization**: Power BI / Tableau

## 📁 Repository Structure
```text
customer-feedback-ai/
├── README.md                  <- Project documentation
├── data/
│   └── sample_feedback.csv    <- 50-row sample dataset to test the pipeline
├── sql/  
│   ├── 01_setup_schema.sql    <- DDL scripts to create datasets and tables
│   ├── 02_ai_analytics.sql    <- Processing queries for sentiment & topic extraction
├── dashboards/
│   └── feedback_insights.pbix <- Exported Power BI dashboard file
```

## 📦 Dataset Content
This project utilises publicly available Kaggle datasets to simulate a real-world omnichannel support environment:

### 🛍️ E-Commerce 100k Reviews
Used for product sentiment analysis and topic classification.

### 🎫 Customer Support Tickets
Used for support ticket ingestion and priority routing.

## ⚙️ Installation and Setup
Configure Google Cloud: Ensure you have a GCP project with billing enabled and the BigQuery and Vertex AI APIs turned on.

Set up a Cloud Resource Connection: Create a connection in BigQuery (e.g., us.example_connection) and grant the Vertex AI User role to the generated service account.

Execute SQL Pipelines: Run the scripts located in the sql/ folder within your BigQuery console to create the necessary tables, configure the remote models, and generate analytical insights.

## 🚀 Results and Evaluation
By transitioning from manual feedback review to this automated data pipeline, the system successfully categorizes raw text using BigQuery's built-in machine learning functions (ML.GENERATE_TEXT / AI.C[...]

## 📝 License
This project is licensed under the MIT License.
