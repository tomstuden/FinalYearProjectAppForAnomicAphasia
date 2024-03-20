import os
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from ibm_watson import TextToSpeechV1
from ibm_cloud_sdk_core.authenticators import IAMAuthenticator
import numpy as np
import pandas as pd
from PIL import Image
from glob import glob
from tqdm import tqdm
import tempfile
import base64
import tensorflow as tf
import requests

app = Flask(__name__)
CORS(app)

# Load your model
model = tf.keras.models.load_model("D:\\FinalYearProject\\Model\\g-cnn-generator_30122023_05.h5")

# setting up tts
authenticator = IAMAuthenticator('Qmq7EWfWgdHM5AuQDiHQ2p6l3sHfASovVaI5VGmy9oO_')
text_to_speech = TextToSpeechV1(authenticator=authenticator)
text_to_speech.set_service_url('https://api.au-syd.text-to-speech.watson.cloud.ibm.com/instances/6b85770b-1316-49a7-9e53-1a1cbb6a45cc')

# Define the directory to save audio files on desktop
DESKTOP_DIRECTORY = os.path.expanduser(r"D:\FinalYearProject\User Interface\flutter UI\flutterUI\flutter_first_draft\assets\AudioFiles")

# Initialize image_array globally
image_array = np.ones((64, 64)) * 255

def convert_data_to_image(data):
    # Create a blank image array with a white background
    image_array = np.ones((64, 64)) * 255  # Initialize with white background

    # Draw points on the image array
    for point in data:
        x = int(point['x'])
        y = int(point['y'])
        # Ensure the point is within the bounds of the image
        if 0 <= x < 64 and 0 <= y < 64:
            image_array[y, x] = 0  # Mark the point with black color

    # Convert the image array to a PIL image
    image = Image.fromarray(image_array.astype('uint8'))
    
    return image

def clear_image(image_array):
    image_array.fill(255)
    return image_array

@app.route('/api/drawings', methods=['POST', 'OPTIONS'])
def process_data():
    global image_array  # Access the global image_array variable

    if request.method == 'OPTIONS':
        # Handle pre-flight request
        response = jsonify({'message': 'Allowing CORS'})
        response.headers['Access-Control-Allow-Origin'] = '*'  # Allow requests from any origin
        response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'  # Allow POST and OPTIONS methods
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type'  # Allow Content-Type header
        return response, 200

    data = request.json  # Get the JSON data from the request
    if not data:
        return jsonify({'error': 'No data received'}), 400
    
    print("data received")
    # Convert the data to an image
    image = convert_data_to_image(data)
    
    # Convert the image to the format expected by your model
    image = np.array(image) / 255.0  # Normalize the image
    image = np.expand_dims(image, axis=0)  # Add batch dimension
    
    # Load words
    words = []
    INPUT_ROOT = 'D:\\FinalYearProject\\QuickdrawDataCSV'
    INPUT_DIR = 'train_simplified'
    filenames = glob(os.path.join(INPUT_ROOT, INPUT_DIR, '*.csv'))
    
    for filename in tqdm(filenames):
        words.append(pd.read_csv(filename, nrows=1)['word'].values[0])
    
    y_pred_single = model.predict(image)
    
    # Get the index of the highest predicted outcome
    top_prediction_index = np.argmax(y_pred_single[0])

    # Get the label for the highest predicted outcome
    top_prediction_label = words[top_prediction_index]

    # Synthesize text to speech
    # Synthesize text to speech with adjusted rate
    response = text_to_speech.synthesize(
    text=top_prediction_label,
    voice='en-US_AllisonV3Voice',
    accept='audio/wav',
    ).get_result()

    # Save the audio content to a file on desktop
    audio_file_path = os.path.join(DESKTOP_DIRECTORY, f"{top_prediction_label}.wav")
    with open(audio_file_path, "wb") as audio_file:
        audio_file.write(response.content)
    
    print(audio_file_path)
    
    # Fetch images for the top prediction label using SERP API
    query = "flaticon" + top_prediction_label + ' icon png'
    site_to_search = "https://www.flaticon.com/"
    params = {
        'engine': 'google_images',
        'q': query,
        'site': site_to_search,
        'api_key': 'a51651938595064a836d91aeafcae77a0490834609bf2bc222be3515c10c6c98',  # Replace 'your_api_key' with your actual API key
    }
    response = requests.get('https://serpapi.com/search', params=params)
    top_prediction_image_url = None
    if response.status_code == 200:
        images_results = response.json().get('images_results', [])
        if images_results:
            top_prediction_image_url = images_results[0]['original']
            print(f"Image URL for '{top_prediction_label}': {top_prediction_image_url}")
    
    # Clear the image array for the next request
    image_array = clear_image(image_array)
    
    top_prediction_image_url = 'https://cdn-icons-png.flaticon.com/512/124/124027.png' #### placeholder while out of serp seraches
    print(f"Image URL for '{top_prediction_label}': {top_prediction_image_url}")

    
    # Return response with top prediction label, image URL, and audio file path
    return jsonify({'top_prediction_label': top_prediction_label, 'top_prediction_image_url': top_prediction_image_url, 'audio_file_path': audio_file_path}), 200

if __name__ == '__main__':
    app.run(debug=True)
