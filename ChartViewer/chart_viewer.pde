import processing.serial.*;

// --- 시리얼 및 포트 설정 변수 ---
Serial myPort;
String targetPort = "";
int baudRate = 115200; 

// --- 그래프 설정 변수 (기존 유지)
int maxADC = 4095; 
int minY = 50;
int maxY;
int yAxisWidth = 50;
int toolbarLeft = 0;

// 데이터 누적 및 스크롤 관련 변수 (기존 유지)
ArrayList<Integer> history;
int dataPointSpacing = 2;
int maxVisiblePoints;
final int NOISE_THRESHOLD = 20;

// 마우스 스크롤 및 차트 상태 변수 (기존 유지)
int currentStartIndex = 0;
int mouseX_prev = 0;
boolean isMouseDragging = false;
boolean chartPaused = false; 
boolean isConnected = false; 

// 버튼 및 콤보 박스 관련 변수
Button connectButton;    // [시작/중지] 버튼
Button continueButton;   // [계속] 버튼 복구
Button resetButton;
ComboBox resolutionComboBox;
ComboBox comPortComboBox;
ComboBox baudRateComboBox;

int buttonHeight = 30;
int buttonY = 10;
int buttonSpacing = 10;
int buttonWidth = 100;

// 해상도 선택지
String[] maxADC_options = {"256", "512", "1024", "2048", "4096", "8192"};
int initialResolutionIndex = 0;

// 포트 및 보드레이트 옵션
String[] availablePorts;
String[] baudRateOptions = {"9600", "115200"};


void setup() {
  size(1600, 800);
  textFont(createFont("Gulim", 16)); 
  
  maxY = height - 30;
  strokeWeight(2);
  
  history = new ArrayList<Integer>();
  maxVisiblePoints = (width - yAxisWidth) / dataPointSpacing;
  
  // 1. COM 포트 목록 가져오기
  availablePorts = Serial.list();
  if (availablePorts.length == 0) {
      availablePorts = new String[]{"N/A"};
  }

  // 2. UI 요소 초기화 및 오른쪽 정렬
  toolbarLeft = width - buttonSpacing;
  
  // 2-1. [초기화] 버튼
  toolbarLeft -= buttonWidth;
  resetButton = new Button("초기화", toolbarLeft, buttonY, buttonWidth, buttonHeight, color(255, 100, 100));
  toolbarLeft -= buttonSpacing;
  
  // 2-2. [계속] 버튼
  toolbarLeft -= buttonWidth;
  continueButton = new Button("계속", toolbarLeft, buttonY, buttonWidth, buttonHeight, color(100, 200, 100));
  toolbarLeft -= buttonSpacing;

  // 2-3. [해상도] ComboBox
  int comboWidth = buttonWidth + 30;
  toolbarLeft -= comboWidth;
  resolutionComboBox = new ComboBox(toolbarLeft, buttonY, comboWidth, buttonHeight, maxADC_options, initialResolutionIndex);
  toolbarLeft -= buttonSpacing;
  
  // 2-4. [시작]/[중지] 버튼
  toolbarLeft -= buttonWidth + 50;
  connectButton = new Button("시작", toolbarLeft, buttonY, buttonWidth, buttonHeight, color(0, 150, 0));
  toolbarLeft -= buttonSpacing;
  
  // 2-5. 통신속도 ComboBox
  comboWidth = buttonWidth + 30;
  toolbarLeft -= comboWidth;
  baudRateComboBox = new ComboBox(toolbarLeft, buttonY, comboWidth, buttonHeight, baudRateOptions, 1);
  toolbarLeft -= buttonSpacing;
  
  // 2-6. COM 포트 ComboBox
  comboWidth = buttonWidth + 30;
  toolbarLeft -= comboWidth;
  comPortComboBox = new ComboBox(toolbarLeft, buttonY, comboWidth, buttonHeight, availablePorts, 0);

  // 초기 해상도 및 통신 설정
  maxADC = Integer.parseInt(maxADC_options[resolutionComboBox.selectedIndex]);
  targetPort = availablePorts[comPortComboBox.selectedIndex];
  baudRate = Integer.parseInt(baudRateOptions[baudRateComboBox.selectedIndex]);
}

void draw() {
  background(0);
  
  // 1. 그리드 및 축 그리기
  drawGridAndAxes();

  // 2. 누적된 데이터 그래프 그리기
  strokeWeight(2);
  drawDataChart();

  // 3. 버튼 및 콤보 박스 그리기
  drawButtons();

  // 4. 차트 정지 상태 표시
  if (chartPaused && isConnected) {
    float prevSize = g.textSize;
    noStroke();
    fill(255, 0, 0);
    textSize(24);
    textAlign(CENTER);
    text("일시중지 (캡처 중)", toolbarLeft / 2, minY - 15);
    textSize(prevSize);
  }

  // 시리얼 버퍼 확인 (연결된 경우에만)
  if (myPort != null && isConnected) {
      while (myPort.available() > 0) {
          serialEvent(myPort);
      }
  }
}

// 콤보 박스 클래스 정의 (기존 유지)
class ComboBox {
  float x, y, w, h;
  String[] options;
  int selectedIndex;
  boolean expanded = false;
  color baseColor = color(50, 50, 50);
  color itemColor = color(80, 80, 80);
  color hoverColor = color(120, 120, 120);

  ComboBox(float x, float y, float w, float h, String[] options, int defaultIndex) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.options = options;
    this.selectedIndex = defaultIndex;
  }

  boolean isMouseOver() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
  
  boolean isMouseOverItem(int index) {
      if (!expanded) return false;
      float itemY = y + h + index * h;
      return mouseX >= x && mouseX <= x + w && mouseY >= itemY && mouseY <= itemY + h;
  }

  void display() {
    // 콤보 박스 본체 (현재 선택 값)
    stroke(255);
    strokeWeight(1);
    
    fill(baseColor);
    rect(x, y, w, h, 7);
    
    noStroke();
    fill(255);
    textAlign(LEFT, CENTER);
    textSize(14);
    
    String prefix = "";
    if (this == resolutionComboBox) prefix = "해상도: ";
    else if (this == comPortComboBox) prefix = "포트: ";
    else if (this == baudRateComboBox) prefix = "속도: ";
    
    text(prefix + options[selectedIndex], x + 10, y + h / 2);
    
    textAlign(CENTER, CENTER);
    text("▼", x + w - 15, y + h / 2);

    if (expanded) {
      for (int i = 0; i < options.length; i++) {
        float itemY = y + h + i * h;
        
        stroke(255);
        strokeWeight(1); 
        
        if (isMouseOverItem(i)) {
          fill(hoverColor);
        } else {
          fill(itemColor);
        }
        rect(x, itemY, w, h, 0);
        
        noStroke();
        fill(255);
        textAlign(LEFT, CENTER);
        text(options[i], x + 10, itemY + h / 2);
      }
    }
    strokeWeight(2);
    stroke(255);
  }
  
  // 콤보 박스 항목 선택 시 설정을 업데이트하는 함수
  void handleSelection() {
      int newIndex = -1;
      for (int i = 0; i < options.length; i++) {
          if (isMouseOverItem(i)) {
              newIndex = i;
              break;
          }
      }
      
      if (newIndex != -1) {
          selectedIndex = newIndex;
          
          if (this == resolutionComboBox) {
              int oldMaxADC = maxADC;
              maxADC = Integer.parseInt(options[selectedIndex]);
               if (maxADC != oldMaxADC) {
                  // 해상도 변경 시 데이터 초기화 및 실시간 모드 강제 전환
                  history.clear(); 
                  currentStartIndex = 0;
                  chartPaused = false; 
              }
          } else if (this == comPortComboBox) {
              targetPort = options[selectedIndex];
          } else if (this == baudRateComboBox) {
              baudRate = Integer.parseInt(options[selectedIndex]);
          }
      }
      expanded = false;
  }
}

// 버튼 클래스 정의 (기존 유지)
class Button {
  String label;
  float x, y, w, h;
  color baseColor;
  color hoverColor;
  
  Button(String label, float x, float y, float w, float h, color baseColor) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.baseColor = baseColor;
    this.hoverColor = color(red(baseColor) + 30, green(baseColor) + 30, blue(baseColor) + 30);
  }
  
  boolean isMouseOver() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
  
  void display() {
    // connectButton의 경우 연결 상태에 따라 색상과 텍스트를 업데이트
    if (this == connectButton) {
        if (isConnected) {
            this.label = "중지";
            this.baseColor = color(150, 0, 0); // 빨간색
        } else {
            this.label = "시작";
            this.baseColor = color(0, 150, 0); // 초록색
        }
        this.hoverColor = color(red(baseColor) + 30, green(baseColor) + 30, blue(baseColor) + 30);
    }
    
    stroke(255);
    strokeWeight(1);
    
    // 마우스 오버 색상
    if (isMouseOver() && !isAnyComboBoxExpanded()) {
      fill(hoverColor);
    } else {
      fill(baseColor);
    }
    rect(x, y, w, h, 7);
    
    noStroke();
    fill(0);
    textAlign(CENTER, CENTER);
    textSize(14);
    text(label, x + w / 2, y + h / 2);
  }
}

// 모든 콤보 박스 중 하나라도 열려 있는지 확인하는 헬퍼 함수
boolean isAnyComboBoxExpanded() {
    ComboBox[] allBoxes = {resolutionComboBox, comPortComboBox, baudRateComboBox};
    for (ComboBox box : allBoxes) {
        if (box.expanded) return true;
    }
    return false;
}

// 버튼 및 콤보 박스 그리기 함수 (전체 UI 반영)
void drawButtons() {
  comPortComboBox.display();
  baudRateComboBox.display();
  resolutionComboBox.display();
  connectButton.display();
  continueButton.display();
  resetButton.display();
  
  strokeWeight(2);
  stroke(255);
}

// 콤보 박스 영역 확인 함수 (전체 UI 반영)
boolean isMouseOverComboBoxArea() {
    ComboBox[] allBoxes = {resolutionComboBox, comPortComboBox, baudRateComboBox};
    for (ComboBox box : allBoxes) {
        // 콤보 박스 본체 영역
        if (mouseX >= box.x && mouseX <= box.x + box.w && mouseY >= box.y && mouseY <= box.y + box.h) {
            return true;
        }
        // 확장된 드롭다운 항목 영역
        if (box.expanded) {
            float dropdownHeight = box.h * box.options.length;
            if (mouseX >= box.x && mouseX <= box.x + box.w && 
                mouseY >= box.y + box.h && mouseY <= box.y + box.h + dropdownHeight) {
                return true;
            }
        }
    }
    return false;
}

// 시리얼 포트 연결/해제 함수
void toggleSerialConnection() {
    if (isConnected) {
        // 중지 (연결 끊기)
        if (myPort != null) {
            myPort.stop();
            myPort = null;
        }
        isConnected = false;
        chartPaused = true; // 중지 시 차트도 PAUSED
    } else {
        // 시작 (연결 시도)
        if (targetPort.equals("N/A") || targetPort.isEmpty()) {
            return;
        }
        try {
            myPort = new Serial(this, targetPort, baudRate);
            myPort.clear();
            myPort.bufferUntil('\n');
            history.clear();
            currentStartIndex = 0;
            isConnected = true;
            chartPaused = false; // 연결 성공 시 실시간 캡처 시작
        } catch (Exception e) {
            myPort = null;
            isConnected = false;
            // 연결 실패 시 버튼 색상이 시작으로 유지되도록 함
        }
    }
}

long lastClickTime = 0;
final int DOUBLE_CLICK_TIME = 250; // 밀리초(ms), 250ms 이내 두 번 클릭 시 더블 클릭으로 간주

void handleDoubleClick() {
  chartPaused ^= true;
}

// mousePressed() 함수 수정
void mousePressed() {
  
  // 1. 콤보 박스 클릭 처리 
  ComboBox[] allBoxes = {resolutionComboBox, comPortComboBox, baudRateComboBox};
  boolean boxClicked = false;

  // 마우스 왼쪽 버튼(LEFT)이 눌렸을 때만 처리
  if (mouseButton == LEFT) {
    long currentTime = millis();
    
    // 현재 시간과 이전 클릭 시간의 차이가 DOUBLE_CLICK_TIME보다 작으면 더블 클릭
    if (currentTime - lastClickTime < DOUBLE_CLICK_TIME) {
      // 더블 클릭 함수 호출
      handleDoubleClick();
      
      // 더블 클릭 후 다음 클릭이 바로 감지되지 않도록 시간을 리셋합니다.
      lastClickTime = 0; 
    } else {
      // 첫 번째 클릭 시간 기록
      lastClickTime = currentTime;
    }
  }

  // 항목 클릭 처리 (확장된 상태에서)
  for (ComboBox box : allBoxes) {
      if (box.expanded) {
          box.handleSelection();
          return; 
      }
  }
  
  // 본체 클릭 처리 (확장)
  for (ComboBox box : allBoxes) {
      if (box.isMouseOver()) {
          box.expanded = true;
          boxClicked = true;
          // 다른 박스는 닫기
          for (ComboBox otherBox : allBoxes) {
              if (otherBox != box) otherBox.expanded = false;
          }
          return; 
      }
  }

  // 콤보박스 외부 클릭 시 모두 닫기
  if (!boxClicked) {
      for (ComboBox box : allBoxes) {
          box.expanded = false;
      }
  }


  // 2. 버튼 클릭 처리
  if (connectButton.isMouseOver()) {
    toggleSerialConnection();
    return;
  }
  
  // [계속] 버튼 처리 (PAUSED 상태 해제)
  if (continueButton.isMouseOver()) {
    if (isConnected) { // 연결된 상태에서만 [계속]이 의미 있음
        chartPaused = false;
        // 가장 최근 데이터로 스크롤
        if (history.size() > maxVisiblePoints) {
            currentStartIndex = history.size() - maxVisiblePoints;
        } else {
            currentStartIndex = 0;
        }
    }
    return;
  } 
  
  if (resetButton.isMouseOver()) {
    history.clear();
    currentStartIndex = 0;
    // 초기화 후 연결된 경우 실시간 모드로, 아니면 PAUSED 상태 유지
    chartPaused = isConnected ? false : true; 
    return;
  }
  
  // 3. 차트 영역 드래그 준비: 마우스 왼쪽 버튼(LEFT)인 경우에만 준비
  if (mouseY > minY && mouseButton == LEFT) { 
    mouseX_prev = mouseX;
    isMouseDragging = true;
  }
}

// 마우스 버튼을 놓을 때 호출됨 (기존과 동일)
void mouseReleased() {
  isMouseDragging = false;
}

// mouseDragged() 함수 (기존과 동일: 드래그 시 PAUSED)
void mouseDragged() {
  if (!isMouseDragging || mouseY < minY) return;
  
  // 드래그가 시작되는 순간 PAUSED 모드 설정
  chartPaused = true; 

  int deltaX = mouseX - mouseX_prev;
  int deltaPoints = round((float)deltaX / dataPointSpacing);
  
  currentStartIndex -= deltaPoints;
  
  int maxIndex = history.size() > maxVisiblePoints ? history.size() - maxVisiblePoints : 0;
  currentStartIndex = max(0, currentStartIndex);
  currentStartIndex = min(maxIndex, currentStartIndex);
  
  mouseX_prev = mouseX;
}


void drawGridAndAxes() {
  // 그리드 및 축 그리기
  stroke(255);
  line(yAxisWidth, minY, yAxisWidth, maxY);
  line(yAxisWidth, maxY, width, maxY);
  
  int numLevels = 4;
  int levelSpacing = maxADC / numLevels;
  
  for (int i = 0; i <= numLevels; i++) {
    int adcValue = levelSpacing * i;
    float y = map(adcValue, 0, maxADC, maxY, minY);
    
    // 그리드 점선
    stroke(50); 
    for (int j = yAxisWidth; j < width; j += 10) {
      line(j, y, j + 5, y);
    }
    
    // 축 텍스트
    noStroke(); 
    fill(255);
    textAlign(RIGHT);
    
    // 일반 레벨 값 표시
    text(String.valueOf(adcValue), yAxisWidth - 5, y + 4);
    
    // MAX 값 표시 개선: 두 줄로 분리
    if (i == numLevels) {
        // "MAX" 텍스트를 위쪽 (y - 12)에 표시
        text("MAX", yAxisWidth - 5, minY + 4 - 12); 
    }
  }
  strokeWeight(2); // 그래프를 위한 선 굵기
}

void drawDataChart() {
    if (history.isEmpty()) return;

    int startIndex = currentStartIndex;
    
    if (history.size() < maxVisiblePoints) {
        startIndex = 0;
    }

    int endIndex = min(history.size(), startIndex + maxVisiblePoints);

    if (endIndex <= startIndex) return;
    
    int lastDrawnValue = history.get(startIndex);
    
    float currentX = yAxisWidth;
    
    strokeWeight(2);

    for (int i = startIndex; i < endIndex; i++) {
        int currentValue = history.get(i);
        
        if (abs(currentValue - lastDrawnValue) > NOISE_THRESHOLD) {
            stroke(255, 0, 0); // Red (튀는 값)
        } else {
            stroke(0, 255, 0); // Green (일반 값)
        }
        
        int currentY = (int) map(currentValue, 0, maxADC, maxY, minY);
        int lastY = (int) map(lastDrawnValue, 0, maxADC, maxY, minY);
        
        if (i > startIndex) { 
              line(currentX - dataPointSpacing, lastY, currentX, currentY);
        }
        
        currentX += dataPointSpacing;
        lastDrawnValue = currentValue;
    }
}

void serialEvent(Serial p) {
  if (myPort == null) return;
  
  try {
    String inString = p.readStringUntil('\n');

    if (inString != null) {
      inString = trim(inString);
      
      int inValue = Integer.parseInt(inString);
      
      inValue = constrain(inValue, 0, maxADC);
      
      history.add(inValue);
      
      if (!chartPaused) {
          if (history.size() > maxVisiblePoints) {
              currentStartIndex = history.size() - maxVisiblePoints;
          } else {
              currentStartIndex = 0;
          }
      }
    }
  } catch (NumberFormatException e) {
    // 숫자가 아닌 데이터 무시
  }
}
