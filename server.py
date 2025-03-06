from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)

# Store scanned data in memory for testing
scanned_records = []

@app.route('/mark-attendance', methods=['POST'])
def mark_attendance():
    try:
        data = request.json
        
        # Add timestamp to the received data
        data['timestamp'] = datetime.now().isoformat()
        scanned_records.append(data)
        
        return jsonify({
            'status': 'success',
            'message': 'Attendance marked successfully',
            'data': data
        }), 200
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 400

@app.route('/get-records', methods=['GET'])
def get_records():
    return jsonify(scanned_records)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)