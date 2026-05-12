---
type: instagram-video
date: 2026-05-12
author: Arjay McCandless
url: https://www.instagram.com/reel/DYNmUCapShx
category: Job/Career
tags: ['#tech/python', '#tech/data-science', '#tech/data-analysis', '#career/tips']
content_hash: 5ff43b9fcf34b92c08753732e07b3870
transcript_status: complete
ai_model: models/gemini-2.5-flash-lite
processor: 
---
# Job/Career by Arjay McCandless

> **AI Summary:** This content outlines a practical approach to designing and building web scrapers, detailing steps from initial data retrieval to robust system design for ongoing data collection.

## Extracted Content
## Designing and Building a Web Scraper

This guide provides a comprehensive approach to designing and building web scrapers, covering various skill levels and best practices.

**Key Skills & Concepts:**

*   [[Python]] scripting for data retrieval.
*   Using libraries like [[Requests]] and [[Beautiful Soup]] for HTML parsing.
*   Leveraging browser developer tools (network tab) to identify API requests.
*   Understanding and respecting [[robots.txt]] for web scraping ethics.
*   Utilizing [[Playwright]] for advanced scraping capabilities including JavaScript rendering and user interactions.
*   Database integration for efficient data storage and retrieval.
*   Implementing robust error handling and resilience mechanisms: retries, exponential backoff, and change alerts.

**Actionable Advice:**

1.  **Inspect Network Traffic:** Open developer tools in your browser and examine the network tab to understand how a website fetches data.
2.  **Prioritize APIs:** If available, use a website's official API to fetch data directly, bypassing the need to parse HTML or JavaScript.
3.  **Respect `robots.txt`:** Always check the `robots.txt` file to ensure scraping is permitted by the website's owner.
4.  **Automate with `Playwright`:** For complex websites requiring JavaScript rendering or button clicks, use tools like `Playwright`.
5.  **Store Data Efficiently:** Write scraped data to a database to avoid repeated scraping and reduce the risk of being banned.
6.  **Build Resilient Systems:** Implement strategies like retries, exponential backoff, and alerts for external requests to ensure scraper stability and notify you of website changes.

## Raw Transcript
How would you design and build a web scraper? Okay, well, I would just write a simple Python script. We'd first get the raw HTML using requests, then we'd use beautiful soup to parse that HTML and extract whatever information we need. I'd start by opening up the website and Chrome, opening up developer tools, and then looking at the network tab to see what information that website is actually getting on the back end. Then I'd copy those API requests myself so I could get information directly from their API without having to parse or scrape a bunch of HTML and JavaScript. I'd start by reading the robots.txt to make sure the website allows scraping, and if it doesn't, I'd look for an official API. Then we'll build a simple system we can use to scrape any website. Every 24 hours, we'll use playwright to scrape data from every single site. This lets us do things like read HTML, but also press buttons, login, render JavaScript, all that fun stuff. After we scrape data from a site, we'll take that data and write it to our database. Then if we want to access that data again and again, we can make requests to our database instead of having to scrape the site. This reduces our chances of getting banned. And of course, for all requests to make to external websites, plot things like retries, exponential back off, and alerts if something on the website changes, we need to update the scraper.


---
### Original Caption
* Webscraping: Intern vs Jr vs Senior. 

If you’re looking for daily system design practice & community to learn more, check out my app The Daily Dev (link in bio).

#systemdesign #coding #programming #webscraping
