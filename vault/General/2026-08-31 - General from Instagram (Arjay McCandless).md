---
type: instagram-video
date: 2026-08-31
author: Arjay McCandless
url: https://www.instagram.com/reel/DcruU2qAwGd
category: General
tags: ['#tech/data-science', '#tech/machine-learning', '#general/ideas', '#inbox/youtube']
locations: []
hidden_locations: []
content_hash: 208cc225d1996bbb6cb84e57af257129
transcript_status: complete
ai_model: models/gemini-2.5-flash-lite
processor: 
---
# General by Arjay McCandless

> **AI Summary:** Explains the CAP theorem in distributed systems, focusing on consistency, availability, and partition tolerance, and provides examples of when to prioritize each.

## Extracted Content
### Understanding the CAP Theorem

*   **CAP Theorem Overview:** The CAP theorem states that a distributed data store can only provide two out of three guarantees: Consistency, Availability, and Partition Tolerance.
*   **Key Definitions:**
    *   **Consistency:** All reads return the same value, meaning all servers reflect the latest updates rapidly.
    *   **Availability:** The system responds to requests even if some components are down.
    *   **Partition Tolerance:** The system continues to function despite network failures that separate components.
*   **Practical Application:** Since network failures (partitions) are inevitable, the choice is between Consistency and Availability. Choosing Availability means potentially returning stale data, while choosing Consistency means the system might not respond at all to avoid returning incorrect data.

### Choosing Between Consistency and Availability

*   **Prioritize Availability:** Suitable for applications where stale data is acceptable, such as like counts on [[Instagram]] or weekly business analytics.
*   **Prioritize Consistency:** Essential for critical transactions like bank transfers or managing limited inventory (e.g., concert tickets) where data accuracy is paramount, even if it means the system cannot respond during a partition.

## Raw Transcript
What is your major here at MIT? Uh, 630, computer sign. What is the cap theorem? Oh, I don't think I know this one. This is the cap theorem. Traditionally, the cap theorem states you can only ever have two of the three. Consistency, availability, and partition tolerance. But this isn't exactly true nowadays. What do those things even mean? Consistency just means that all reads to your system for the same thing should return the same value. If a value is set on one server, all other servers should start returning that value as fast as possible. Availability means that we return a response even if part of the system is down. For example, if we have a primary database plus a replica, even if one of those is down, which would still return some response to the user, even if it contains stale data. Partition tolerance just means that our system continues to function even if it is somehow separated by the network, which is inevitable because networks always fail. So how do I know which one to actually choose? Because networks always fail, we have to choose partition tolerance, which means our choice is actually just between availability and consistency. If we choose availability, it means that during a partition, we might not return the most up-to-date data. But if we choose consistency, it means that we won't return any data at all because we can't risk returning stale data. OK, can you give me some examples of when you might choose each? For things where returning stale data isn't a problem like how many likes you got on Instagram or some business analytics that are only looked at once a week, then picking availability is usually better. For things where the data can't be wrong, like how much money you have in your bank before you make a wire transfer, or how many concert tickets you have before you sell the last one, then it's better to just not return a response rather than risk being wrong.


---
### Original Caption
* MIT CS Major vs Distributed Systems 

What is the CAP theorem?

Credit to @voodiesinterviews for the original clip! #coding #programming #systemdesign #csmajors
