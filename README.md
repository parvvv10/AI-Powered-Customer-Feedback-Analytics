# 🧠 AI-Powered Customer Feedback Intelligence System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Google Cloud](https://img.shields.io/badge/Google_Cloud-BigQuery_%7C_Vertex_AI-blue.svg)](https://cloud.google.com/)

## 📌 Project Overview
This end-to-end data engineering and analytics project ingests unstructured customer feedback from multiple channels (product reviews, support tickets, and social media) into a cloud data warehouse. It utilizes Google Cloud's Natural Language Processing (NLP) capabilities to categorize sentiment, extract key topics, and score feedback. The structured insights are then surfaced via an interactive BI dashboard, enabling data-driven decision-making in near real-time.

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
