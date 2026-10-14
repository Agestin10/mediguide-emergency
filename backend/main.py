from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import sqlite3
import math

app = FastAPI()

DATABASE = "mediguide.db"


# =================================================
# CREATE DATABASE
# =================================================

def create_database():
    connection = sqlite3.connect(DATABASE)
    cursor = connection.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS emergency_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            patient_name TEXT NOT NULL,
            age INTEGER NOT NULL,
            gender TEXT NOT NULL,
            phone TEXT,
            emergency_condition TEXT NOT NULL,
            additional_notes TEXT,
            latitude REAL,
            longitude REAL,
            status TEXT NOT NULL
        )
    """)

    # Add emergency requirement columns if they do not already exist
    cursor.execute("PRAGMA table_info(emergency_requests)")
    existing_columns = {
        row[1] for row in cursor.fetchall()
    }
    
    new_columns = {
        "icu_required": "INTEGER DEFAULT 0",
        "normal_bed_required": "INTEGER DEFAULT 0",
        "oxygen_required": "INTEGER DEFAULT 0",
        "ventilator_required": "INTEGER DEFAULT 0",
        "specialist_required": "INTEGER DEFAULT 0",
        "other_facility": "TEXT DEFAULT ''",
        "selected_hospital_id": "INTEGER",
        "hospital_selected_at": "TEXT"
    }

    for column_name, column_type in new_columns.items():
        if column_name not in existing_columns:
            cursor.execute(
                f"""
                ALTER TABLE emergency_requests
                ADD COLUMN {column_name} {column_type}
                """
            )

    try:
        cursor.execute(
            "ALTER TABLE emergency_requests ADD COLUMN journey_status TEXT"
        )
    except sqlite3.OperationalError:
        pass

    connection.commit()
    connection.close()


create_database()


# =================================================
# INITIAL EMERGENCY REQUEST MODEL
# =================================================
# At this stage, the normal user only sends location.
# Patient details will be entered by the ambulance assistant.
# =================================================

class EmergencyRequest(BaseModel):

    latitude: float
    longitude: float


# =================================================
# AMBULANCE ASSESSMENT MODEL
# =================================================
# This data will be entered by the ambulance assistant
# after reaching the patient.
# =================================================

class AmbulanceAssessment(BaseModel):

    patient_name: str
    age: int
    gender: str
    phone: str = ""
    emergency_condition: str
    additional_notes: str = ""

    icu_required: bool = False
    normal_bed_required: bool = False
    oxygen_required: bool = False
    ventilator_required: bool = False
    specialist_required: bool = False
    other_facility: str = ""


# =================================================
# HOME
# =================================================

@app.get("/")
def home():

    return {
        "message": "MediGuide Emergency API is running"
    }


# =================================================
# REGISTER INITIAL EMERGENCY
# =================================================

@app.post("/emergency")
def create_emergency(request: EmergencyRequest):

    connection = sqlite3.connect(DATABASE)
    cursor = connection.cursor()

    # -------------------------------------------------
    # At initial registration:
    #
    # Patient details are not known yet.
    # They will be entered later by ambulance assistant.
    #
    # Existing database columns are NOT NULL,
    # therefore temporary empty values are inserted.
    # -------------------------------------------------

    cursor.execute("""
        INSERT INTO emergency_requests
        (
            patient_name,
            age,
            gender,
            phone,
            emergency_condition,
            additional_notes,
            latitude,
            longitude,
            status
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        "",
        0,
        "",
        "",
        "",
        "",
        request.latitude,
        request.longitude,
        "REQUESTED"
    ))

    request_id = cursor.lastrowid

    connection.commit()
    connection.close()

    return {
        "message": "Emergency request registered successfully",
        "request_id": request_id,
        "status": "REQUESTED",
        "latitude": request.latitude,
        "longitude": request.longitude
    }


# =================================================
# UPDATE EMERGENCY WITH AMBULANCE ASSESSMENT
# =================================================

@app.put("/emergencies/{request_id}/assessment")
def update_emergency_assessment(
    request_id: int,
    assessment: AmbulanceAssessment
):
    connection = sqlite3.connect(DATABASE)
    cursor = connection.cursor()

    cursor.execute(
        """
        SELECT id
        FROM emergency_requests
        WHERE id = ?
        """,
        (request_id,)
    )

    existing_request = cursor.fetchone()

    if existing_request is None:
        connection.close()

        return {
            "message": "Emergency request not found"
        }

    cursor.execute("""
        UPDATE emergency_requests
        SET
            patient_name = ?,
            age = ?,
            gender = ?,
            phone = ?,
            emergency_condition = ?,
            additional_notes = ?,

            icu_required = ?,
            normal_bed_required = ?,
            oxygen_required = ?,
            ventilator_required = ?,
            specialist_required = ?,
            other_facility = ?,

            status = ?

        WHERE id = ?
    """, (
        assessment.patient_name,
        assessment.age,
        assessment.gender,
        assessment.phone,
        assessment.emergency_condition,
        assessment.additional_notes,

        int(assessment.icu_required),
        int(assessment.normal_bed_required),
        int(assessment.oxygen_required),
        int(assessment.ventilator_required),
        int(assessment.specialist_required),
        assessment.other_facility,

        "ASSESSED",

        request_id
    ))

    connection.commit()
    connection.close()

    return {
        "message": "Ambulance assessment saved successfully",
        "request_id": request_id,
        "status": "ASSESSED",

        "emergency_requirements": {
            "icu_required": assessment.icu_required,
            "normal_bed_required": assessment.normal_bed_required,
            "oxygen_required": assessment.oxygen_required,
            "ventilator_required": assessment.ventilator_required,
            "specialist_required": assessment.specialist_required,
            "other_facility": assessment.other_facility
        }
    }


# =================================================
# GET ALL EMERGENCY REQUESTS
# =================================================

@app.get("/emergencies")
def get_emergencies():

    connection = sqlite3.connect(DATABASE)

    connection.row_factory = sqlite3.Row

    cursor = connection.cursor()

    cursor.execute("""
        SELECT *
        FROM emergency_requests
        ORDER BY id DESC
    """)

    rows = cursor.fetchall()

    connection.close()

    return [dict(row) for row in rows]


# =================================================
# DUMMY AMBULANCES
# =================================================

ambulances = [

    {
        "ambulance_id": "AMB-001",
        "driver_name": "Ravi",
        "phone": "9876543210",
        "status": "Available"
    },

    {
        "ambulance_id": "AMB-002",
        "driver_name": "Kumar",
        "phone": "9876543211",
        "status": "Available"
    },

    {
        "ambulance_id": "AMB-003",
        "driver_name": "Arun",
        "phone": "9876543212",
        "status": "Busy"
    }

]


# =================================================
# GET AVAILABLE AMBULANCES
# =================================================

@app.get("/ambulances")
def get_ambulances():

    return ambulances

# ==========================================
# STEP 9: DUMMY HOSPITAL DATA
# ==========================================

hospitals = [
    {
        "hospital_id": 1,
        "hospital_name": "City Care Hospital",
        "address": "Coimbatore - Sample Address",
        "latitude": 11.0200,
        "longitude": 76.9600,
        "icu_beds": 2,
        "normal_beds": 10,
        "oxygen_available": True,
        "ventilator_available": True,
        "specialist_available": True
    },
    {
        "hospital_id": 2,
        "hospital_name": "Green Life Hospital",
        "address": "Coimbatore - Sample Address",
        "latitude": 11.0300,
        "longitude": 76.9700,
        "icu_beds": 0,
        "normal_beds": 8,
        "oxygen_available": True,
        "ventilator_available": False,
        "specialist_available": False
    },
    {
        "hospital_id": 3,
        "hospital_name": "Gov Medical Centre",
        "address": "Coimbatore - Sample Address",
        "latitude": 11.0100,
        "longitude": 76.9500,
        "icu_beds": 1,
        "normal_beds": 5,
        "oxygen_available": True,
        "ventilator_available": True,
        "specialist_available": True
    }
]


@app.get("/hospitals")
def get_hospitals():
    return hospitals

# ==========================================
# STEP 10: HOSPITAL MATCHING
# ==========================================

class HospitalMatchRequest(BaseModel):
    request_id: int


def calculate_distance(lat1, lon1, lat2, lon2):
    # Haversine formula: straight-line distance in km
    earth_radius = 6371

    lat1 = math.radians(lat1)
    lon1 = math.radians(lon1)
    lat2 = math.radians(lat2)
    lon2 = math.radians(lon2)

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1)
        * math.cos(lat2)
        * math.sin(dlon / 2) ** 2
    )

    c = 2 * math.atan2(
        math.sqrt(a),
        math.sqrt(1 - a)
    )

    return earth_radius * c


@app.get("/match-hospitals/{request_id}")
def match_hospitals(request_id: int):

    # 1. Get patient data from database
    connection = sqlite3.connect(DATABASE)
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    cursor.execute(
        "SELECT * FROM emergency_requests WHERE id = ?",
        (request_id,)
    )

    patient = cursor.fetchone()
    connection.close()

    if patient is None:
        return {"message": "Emergency request not found"}

    if patient["status"] != "ASSESSED":
        return {
            "message": "Patient assessment is not completed"
        }

    if patient["latitude"] is None or patient["longitude"] is None:
        return {"message": "Patient location is missing"}

    # 2. Identify the facilities requested by patient
    requirements = {
        "ICU Bed": bool(patient["icu_required"]),
        "Normal Bed": bool(patient["normal_bed_required"]),
        "Oxygen": bool(patient["oxygen_required"]),
        "Ventilator": bool(patient["ventilator_required"]),
        "Specialist": bool(patient["specialist_required"])
    }

    requested = [
        name for name, required in requirements.items()
        if required
    ]

    if not requested:
        return {
            "message": "No emergency requirements selected"
        }

    ranked_hospitals = []

    # 3. Check every hospital
    for hospital in hospitals:

        available = {
            "ICU Bed": hospital["icu_beds"] > 0,
            "Normal Bed": hospital["normal_beds"] > 0,
            "Oxygen": hospital["oxygen_available"],
            "Ventilator": hospital["ventilator_available"],
            "Specialist": hospital["specialist_available"]
        }

        matched = [
            item for item in requested
            if available[item]
        ]

        missing = [
            item for item in requested
            if not available[item]
        ]

        # 4. Calculate distance from patient location
        distance = calculate_distance(
            patient["latitude"],
            patient["longitude"],
            hospital["latitude"],
            hospital["longitude"]
        )

        all_match = len(matched) == len(requested)

        # 5. Add ranking information to hospital
        ranked_hospitals.append({
            **hospital,
            "distance_km": round(distance, 2),
            "matched_facilities": matched,
            "missing_facilities": missing,
            "matched_count": len(matched),
            "all_requirements_match": all_match
        })

    # 6. Sort:
    # Full match first, then partial match.
    # Within each group, more matched facilities first,
    # then shorter distance first.

    ranked_hospitals.sort(
        key=lambda h: (
            not h["all_requirements_match"],
            -h["matched_count"],
            h["distance_km"]
        )
    )

    return {
        "request_id": request_id,
        "requested_facilities": requested,
        "matched_hospital_count": sum(
            1 for h in ranked_hospitals
            if h["all_requirements_match"]
        ),
        "hospitals": ranked_hospitals
    }


# =================================================
# STEP 11: FREE ROAD ROUTE + ESTIMATED ETA (OSRM)
# =================================================
# This uses the public OSRM demo routing service.
# It provides road distance and estimated duration,
# but NOT live-traffic-aware ETA.
#
# Endpoint:
# GET /route/{request_id}/{hospital_id}
# =================================================

import json
import urllib.error
import urllib.parse
import urllib.request
from fastapi import HTTPException


@app.get("/route/{request_id}/{hospital_id}")
def get_hospital_route(request_id: int, hospital_id: int):
    # 1. Get the patient's saved GPS location.
    connection = sqlite3.connect(DATABASE)
    connection.row_factory = sqlite3.Row
    cursor = connection.cursor()

    cursor.execute(
        "SELECT id, latitude, longitude, status "
        "FROM emergency_requests WHERE id = ?",
        (request_id,)
    )
    patient = cursor.fetchone()
    connection.close()

    if patient is None:
        raise HTTPException(status_code=404, detail="Emergency request not found")

    if patient["latitude"] is None or patient["longitude"] is None:
        raise HTTPException(status_code=400, detail="Patient location is missing")

    # 2. Find the selected hospital from the existing dummy hospital list.
    hospital = next(
        (item for item in hospitals if item["hospital_id"] == hospital_id),
        None
    )

    if hospital is None:
        raise HTTPException(status_code=404, detail="Hospital not found")

    # 3. OSRM expects longitude,latitude order.
    # Coordinates are kept in the backend; no Google billing/API key needed.
    coordinates = (
        f'{patient["longitude"]},{patient["latitude"]};'
        f'{hospital["longitude"]},{hospital["latitude"]}'
    )
    url = (
        "https://router.project-osrm.org/route/v1/driving/"
        + coordinates
        + "?overview=full&geometries=geojson&steps=false"
    )

    request = urllib.request.Request(
        url,
        headers={"User-Agent": "MediGuideEmergencyPrototype/1.0"}
    )

    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            route_data = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        raise HTTPException(
            status_code=502,
            detail="Free routing service is unavailable. Please try again."
        )

    if route_data.get("code") != "Ok" or not route_data.get("routes"):
        raise HTTPException(
            status_code=502,
            detail="No driving route was found for these locations."
        )

    route = route_data["routes"][0]

    # OSRM distance is in metres and duration is in seconds.
    distance_km = round(route["distance"] / 1000, 2)
    duration_minutes = max(1, round(route["duration"] / 60))

    return {
        "request_id": request_id,
        "hospital_id": hospital_id,
        "hospital_name": hospital["hospital_name"],
        "patient_location": {
            "latitude": patient["latitude"],
            "longitude": patient["longitude"]
        },
        "hospital_location": {
            "latitude": hospital["latitude"],
            "longitude": hospital["longitude"]
        },
        "distance_km": distance_km,
        "estimated_duration_minutes": duration_minutes,
        "eta_type": "Estimated road travel time; not live traffic-aware",
        "route_geometry": route["geometry"]
    }


from datetime import datetime, timezone


class HospitalSelection(BaseModel):
    hospital_id: int


class JourneyStatusUpdate(BaseModel):
    status: str


@app.put("/emergencies/{request_id}/select-hospital")
def select_hospital(
    request_id: int,
    selection: HospitalSelection
):
    connection = sqlite3.connect(DATABASE)
    cursor = connection.cursor()

    try:
        cursor.execute(
            "SELECT id, status FROM emergency_requests WHERE id = ?",
            (request_id,)
        )
        emergency = cursor.fetchone()

        if emergency is None:
            raise HTTPException(
                status_code=404,
                detail="Emergency request not found"
            )

        hospital = next(
            (
                item for item in hospitals
                if item["hospital_id"] == selection.hospital_id
            ),
            None
        )

        if hospital is None:
            raise HTTPException(
                status_code=404,
                detail="Hospital not found"
            )

        selected_time = datetime.now(timezone.utc).isoformat()

        cursor.execute(
            """
            UPDATE emergency_requests
            SET selected_hospital_id = ?,
                hospital_selected_at = ?,
                status = ?
            WHERE id = ?
            """,
            (
                selection.hospital_id,
                selected_time,
                "HOSPITAL_SELECTED",
                request_id
            )
        )

        connection.commit()

        return {
            "message": "Hospital selected successfully",
            "request_id": request_id,
            "hospital_id": hospital["hospital_id"],
            "hospital_name": hospital["hospital_name"],
            "status": "HOSPITAL_SELECTED",
            "selected_at": selected_time
        }

    finally:
        connection.close()


@app.put("/emergencies/{request_id}/journey-status")
def update_journey_status(
    request_id: int,
    update: JourneyStatusUpdate
):
    allowed_statuses = [
        "AMBULANCE_STARTED",
        "ON_THE_WAY",
        "REACHED_HOSPITAL",
        "PATIENT_HANDED_OVER",
    ]

    if update.status not in allowed_statuses:
        raise HTTPException(
            status_code=400,
            detail="Invalid journey status"
        )

    conn = sqlite3.connect(DATABASE)
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT id, selected_hospital_id
        FROM emergency_requests
        WHERE id = ?
        """,
        (request_id,)
    )

    emergency = cursor.fetchone()

    if emergency is None:
        conn.close()
        raise HTTPException(
            status_code=404,
            detail="Emergency request not found"
        )

    if emergency[1] is None:
        conn.close()
        raise HTTPException(
            status_code=400,
            detail="Hospital has not been selected yet"
        )

    cursor.execute(
        """
        UPDATE emergency_requests
        SET journey_status = ?
        WHERE id = ?
        """,
        (update.status, request_id)
    )

    conn.commit()
    conn.close()

    return {
        "message": "Journey status updated successfully",
        "request_id": request_id,
        "journey_status": update.status
    }


@app.get("/emergencies/{request_id}/journey-status")
def get_journey_status(request_id: int):
    conn = sqlite3.connect(DATABASE)
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT journey_status
        FROM emergency_requests
        WHERE id = ?
        """,
        (request_id,)
    )

    result = cursor.fetchone()
    conn.close()

    if result is None:
        raise HTTPException(
            status_code=404,
            detail="Emergency request not found"
        )

    return {
        "request_id": request_id,
        "journey_status": result[0]
    }
