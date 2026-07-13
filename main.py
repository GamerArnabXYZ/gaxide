import base64
from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.textinput import TextInput
import requests

class GitPushApp(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(orientation='vertical', padding=15, spacing=15, **kwargs)
        
        # 1. Credentials Inputs
        self.token_input = TextInput(hint_text='Enter GitHub Personal Access Token (PAT)', password=True, size_hint=(1, 0.1))
        self.repo_input = TextInput(hint_text='username/repo-name (e.g., GamerArnabXYZ/test-repo)', size_hint=(1, 0.1))
        
        # 2. File & Commit Inputs
        self.file_path_input = TextInput(hint_text='File Name/Path to update (e.g., index.html)', size_hint=(1, 0.1))
        self.content_input = TextInput(hint_text='Enter file content here...', size_hint=(1, 0.3))
        self.commit_input = TextInput(hint_text='Enter commit message...', size_hint=(1, 0.1))
        
        # Widgets ko add karna
        self.add_widget(self.token_input)
        self.add_widget(self.repo_input)
        self.add_widget(self.file_path_input)
        self.add_widget(self.content_input)
        self.add_widget(self.commit_input)
        
        # 3. Action Button
        self.push_btn = Button(text='Push to GitHub via API', size_hint=(1, 0.1), background_color=(0, 0.6, 0.2, 1))
        self.push_btn.bind(on_press=self.push_to_github)
        self.add_widget(self.push_btn)
        
        # 4. Status Logs
        self.status_log = TextInput(hint_text='Logs and Output will appear here...', readonly=True, size_hint=(1, 0.2))
        self.add_widget(self.status_log)

    def push_to_github(self, instance):
        token = self.token_input.text.strip()
        repo = self.repo_input.text.strip()
        file_path = self.file_path_input.text.strip()
        content = self.content_input.text
        commit_msg = self.commit_input.text.strip() or "Update via Android App"

        if not all([token, repo, file_path]):
            self.status_log.text = "❌ Error: Token, Repo, and File Path are required!"
            return

        self.status_log.text = "⏳ Fetching existing file info (checking for SHA)..."
        
        url = f"https://api.github.com/repos/{repo}/contents/{file_path}"
        headers = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json"
        }

        # Step A: Pehle check karenge ki file pehle se wahan hai ya nahi (SHA code lene ke liye)
        sha = None
        get_res = requests.get(url, headers=headers)
        if get_res.status_code == 200:
            sha = get_res.json().get("sha")

        # Step B: Content ko Base64 mein convert karna (GitHub API standard)
        encoded_content = base64.b64encode(content.encode('utf-8')).decode('utf-8')

        # Step C: API Request Payload tayyar karna
        data = {
            "message": commit_msg,
            "content": encoded_content
        }
        if sha:
            data["sha"] = sha  # Agar file exist karti hai toh SHA dena zaroori hai update ke liye

        self.status_log.text += "\n⏳ Uploading content to GitHub..."
        
        # Step D: PUT request se file create/update karna
        put_res = requests.put(url, headers=headers, json=data)

        if put_res.status_code in [200, 201]:
            self.status_log.text += "\n🚀 SUCCESS! File successfully pushed to GitHub!"
        else:
            self.status_log.text += f"\n❌ FAILED! Code: {put_res.status_code}\nResponse: {put_res.text}"

class MyApp(App):
    def build(self):
        self.title = "GamerArnab API Pusher"
        return GitPushApp()

if __name__ == '__main__':
    MyApp().run()
