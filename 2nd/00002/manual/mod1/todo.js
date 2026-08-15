def calculate_grade(average):
    score = float(average)
    if score >= 90: return "A"
    elif score >= 80: return "B"
    elif score >= 70: return "C"
    elif score >= 60: return "D"
    else: return "F"

def save_student(table, row):
    scores = {f: int(row[f].strip()) for f in SCORE_FIELDS}
    average = Decimal(str(round(sum(scores.values()) / 5, 2)))
    grade = calculate_grade(average)
    table.put_item(Item={
        "studentId": row["studentId"].strip(),
        "examDate": row["examDate"].strip(),
        "name": row["name"].strip(),
        "className": row["className"].strip(),
        "korean": Decimal(scores["korean"]), "english": Decimal(scores["english"]),
        "math": Decimal(scores["math"]), "science": Decimal(scores["science"]),
        "history": Decimal(scores["history"]),
        "average": average, "grade": grade,
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    })