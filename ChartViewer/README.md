## 개요
MCU ADC 측정 값을 라인 차트로 시각화하기 위한 [Processing](https://processing.org) 응용 프로그램 입니다.

## 주요 기능
- 직렬 통신 장치 열거 및 선택
- 통신 속도 선택
- 차트 해상도(Y축) 선택
- ADC 캡처 시작 / 중지
- 이상(Outlier) 데이터(>20) 강조
- 차트 데이터 포인트 표시, 커서 위치 시 캡처 시간, 값 툴팁 표시
- 차트 X축(시간) 스크롤
- 차트 X축 데이터 포인트 너비 마우스 스크롤 조정
- 차트 데이터 초기화

> 💬 이미지 클릭 시 유투브 영상 재생

[![](https://github.com/swengkr/Processing/blob/main/ChartViewer/viewer.png)](https://www.youtube.com/watch?v=NDCOapL57EY)

### 차트 뷰어 소스 코드
```cpp
import processing.serial.*;

Serial myPort;
String targetPort = "";
int baudRate = 115200; 

int maxADC = 4095; 
int minY = 50;
int maxY;
final int yAxisWidth = 50;
int toolbarLeft = 0;

// 데이터 누적 및 스크롤 관련 변수
ArrayList<Integer> history;
ArrayList<Integer> historyTime; // 시간 기록 리스트 추가
int pointSpacing = 3;
int maxVisiblePoints;
final int kNoiseThreshold = 20;

// 마우스 스크롤 및 차트 상태 변수
int currentStartIndex = 0;
int mouseX_prev = 0;
boolean isChartDragging = false;
boolean chartPaused = false; 
boolean isConnected = false; 

// 툴팁 관련 변수 추가
int hoverValue = -1;
int hoverIndex = -1;
float hoverX = -1;
float hoverY = -1;
int pointDiameter = 5; // 점의 지름 설정
int beginTime = 0;

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
int buttonWidth = 80;

// 해상도 선택지
String[] maxADC_options = {"1024", "2048", "4096", "8192"};
int initialResolutionIndex = 0;

// 포트 및 보드레이트 옵션
String[] availablePorts;
String[] baudRateOptions = {"1200","2400","9600","19200","57600","115200"};

PImage imgCursor;
long lastClickTime = 0;
final int kDoubleClickTime = 250; // 밀리초(ms)

void setup() {
  size(1600, 800);
  textFont(createFont("Gulim", 16));
  imgCursor = loadImage("cursor.png"); 

  surface.setTitle("Chart Viewer V0.1");

  maxY = height - 30;
  strokeWeight(2);
  
  history = new ArrayList<Integer>();
  historyTime = new ArrayList<Integer>();
  maxVisiblePoints = (width - yAxisWidth) / pointSpacing;
  
  // COM 포트 목록 가져오기
  availablePorts = Serial.list();
  if (availablePorts.length == 0) {
      availablePorts = new String[]{"N/A"};
  }

  // UI 요소 초기화 및 오른쪽 정렬
  toolbarLeft = width - buttonSpacing;
  
  // [초기화] 버튼
  toolbarLeft -= buttonWidth;
  resetButton = new Button("초기화", toolbarLeft, buttonY, buttonWidth, buttonHeight, color(255, 100, 100));
  toolbarLeft -= buttonSpacing;
  
  // [계속] 버튼
  toolbarLeft -= buttonWidth;
  continueButton = new Button("계속", toolbarLeft, buttonY, buttonWidth, buttonHeight, color(100, 200, 100));
  toolbarLeft -= buttonSpacing;

  // [해상도] ComboBox
  int comboWidth = buttonWidth + 50;
  toolbarLeft -= comboWidth;
  resolutionComboBox = new ComboBox(toolbarLeft, buttonY, comboWidth, buttonHeight, maxADC_options, initialResolutionIndex);
  toolbarLeft -= buttonSpacing;
  
  // [시작]/[중지] 버튼
  toolbarLeft -= buttonWidth + 50;
  connectButton = new Button("시작", toolbarLeft, buttonY, buttonWidth, buttonHeight, color(0, 150, 0));
  toolbarLeft -= buttonSpacing;
  
  // 통신속도 ComboBox
  comboWidth = buttonWidth + 50;
  toolbarLeft -= comboWidth;
  baudRateComboBox = new ComboBox(toolbarLeft, buttonY, comboWidth, buttonHeight, baudRateOptions, 1);
  toolbarLeft -= buttonSpacing;
  
  // COM 포트 ComboBox
  comboWidth = buttonWidth + 50;
  toolbarLeft -= comboWidth;
  comPortComboBox = new ComboBox(toolbarLeft, buttonY, comboWidth, buttonHeight, availablePorts, 0);

  // 초기 해상도 및 통신 설정
  maxADC = Integer.parseInt(maxADC_options[resolutionComboBox.selectedIndex]);
  targetPort = availablePorts[comPortComboBox.selectedIndex];
  baudRate = Integer.parseInt(baudRateOptions[baudRateComboBox.selectedIndex]);
}

void draw() {
  background(0);
  
  // 그리드 및 축 그리기
  drawGridAndAxes();

  // 누적된 데이터 그래프 그리기
  strokeWeight(2);
  drawDataChart();

  // 버튼 및 콤보 박스 그리기
  drawButtons();
  
  // 툴팁 그리기 (마지막에 그려서 다른 요소 위에 표시되도록 함)
  drawTooltip();

  // 차트 정지 상태 표시
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

// 마우스 휠 이벤트 처리 함수 추가
void mouseWheel(MouseEvent event) {
    pointSpacing = constrain(pointSpacing + (-event.getCount()), 3, 20);
}

// 툴팁 그리기 함수 수정
void drawTooltip() {
    if (hoverValue != -1) {
        // 캡처 시간(ms)을 시:분:초.ms 형식으로 변환
        long capturedTimeMs = historyTime.get(hoverIndex) - beginTime;
        long totalSeconds = capturedTimeMs / 1000;
        int hours = (int) (totalSeconds / 3600);
        int minutes = (int) ((totalSeconds % 3600) / 60);
        int seconds = (int) (totalSeconds % 60);
        int milliseconds = (int) (capturedTimeMs % 1000);
        
        // 시:분:초 형식의 텍스트 생성 (nf는 0으로 채워주는 함수)
        String timeText = nf(hours, 2) + ":" + nf(minutes, 2) + ":" + nf(seconds, 2) + "." + nf(milliseconds, 3);
        String valueText = "값: " + hoverValue;
        
        String tooltipText = timeText + "\n" + valueText;
        
        // 툴팁 배경 크기 계산
        float padding = 10;
        // 가장 긴 텍스트를 기준으로 폭 계산
        float textW = max(textWidth(timeText), textWidth(valueText));
        float textH = 2 * (textAscent() + textDescent()); // 두 줄이므로 높이는 두 배
        float tooltipW = textW + 2 * padding;
        float tooltipH = textH + 2 * padding;
        
        // 툴팁 위치 조정
        float x = hoverX + pointDiameter / 2 + 5; // 점 오른쪽으로 약간 이동
        float y = hoverY - tooltipH / 2;
        
        // 화면 경계 체크
        if (x + tooltipW > width) x = hoverX - tooltipW - pointDiameter / 2 - 5;
        if (y < 0) y = 0;
        if (y + tooltipH > height) y = height - tooltipH;

        // 배경
        noStroke();
        fill(50, 50, 50, 200); // 반투명한 회색
        rect(x, y, tooltipW, tooltipH, 5); // 둥근 모서리

        // 텍스트
        fill(255);
        textAlign(LEFT, TOP);
        textSize(14);
        text(tooltipText, x + padding, y + padding);
        
        // 하이라이트 점 그리기 (선택된 점을 강조)
        stroke(255, 255, 0); // 노란색 테두리
        strokeWeight(2);
        noFill();
        ellipse(hoverX, hoverY, pointDiameter + 4, pointDiameter + 4);
    }
}


// 콤보 박스 클래스 정의
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
                  historyTime.clear();
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

// 버튼 클래스 정의
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

  if (isChartDragging) {
    cursor(imgCursor);
  } else {
    cursor(ARROW);
  }

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
            historyTime.clear(); // 연결 시 시간 리스트도 초기화
            currentStartIndex = 0;
            isConnected = true;
            chartPaused = false; // 연결 성공 시 실시간 캡처 시작
            beginTime = millis();
        } catch (Exception e) {
            myPort = null;
            isConnected = false;
            // 연결 실패 시 버튼 색상이 시작으로 유지되도록 함
        }
    }
}

void handleDoubleClick() {
  chartPaused ^= true;
}

void mousePressed() {
  // 콤보 박스 클릭 처리 
  ComboBox[] allBoxes = {resolutionComboBox, comPortComboBox, baudRateComboBox};
  boolean boxClicked = false;

  // 마우스 왼쪽 버튼(LEFT)이 눌렸을 때만 처리
  if (mouseButton == LEFT) {
    long currentTime = millis();
    
    // 현재 시간과 이전 클릭 시간의 차이가 kDoubleClickTime보다 작으면 더블 클릭
    if (currentTime - lastClickTime < kDoubleClickTime) {
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


  // 버튼 클릭 처리
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
    historyTime.clear(); // 초기화 시 시간 리스트도 초기화
    currentStartIndex = 0;
    // 초기화 후 연결된 경우 실시간 모드로, 아니면 PAUSED 상태 유지
    chartPaused = isConnected ? false : true; 
    return;
  }
  
  // 차트 영역 드래그 준비: 마우스 왼쪽 버튼(LEFT)인 경우에만 준비
  if (mouseY > minY && mouseButton == LEFT) { 
    mouseX_prev = mouseX;
    isChartDragging = true;
  }
}

// 마우스 버튼을 놓을 때 호출됨
void mouseReleased() {
  isChartDragging = false;
}

void mouseDragged() {
  if (!isChartDragging || mouseY < minY) return;
  
  // 드래그가 시작되는 순간 PAUSED 모드 설정
  chartPaused = true; 

  int deltaX = mouseX - mouseX_prev;
  int deltaPoints = round((float)deltaX / pointSpacing);
  
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

    // 툴팁 관련 변수 초기화
    hoverValue = -1;
    hoverIndex = -1;

    int startIndex = currentStartIndex;
    
    if (history.size() < maxVisiblePoints) {
        startIndex = 0;
    }

    int endIndex = min(history.size(), startIndex + maxVisiblePoints);

    if (endIndex <= startIndex) return;
    
    int lastDrawnValue = history.get(startIndex);
    
    float currentX = yAxisWidth;
    
    strokeWeight(2);

    // 마우스 감지 거리 설정 (점 반지름 + 여유 공간)
    float tolerance = pointDiameter / 2 + 4; 

    // 1. 선 그래프를 그립니다.
    for (int i = startIndex; i < endIndex; i++) {
        int currentValue = history.get(i);
        
        // 튀는 값/일반 값에 따라 선 색상 결정
        if (abs(currentValue - lastDrawnValue) > kNoiseThreshold) {
            stroke(255, 0, 0); // Red (튀는 값)
        } else {
            stroke(0, 255, 0); // Green (일반 값)
        }
        
        int currentY = (int) map(currentValue, 0, maxADC, maxY, minY);
        int lastY = (int) map(lastDrawnValue, 0, maxADC, maxY, minY);
        
        if (i > startIndex) { 
              line(currentX - pointSpacing, lastY, currentX, currentY);
        }
        
        // 2. 툴팁을 위한 마우스 근접 확인 (선 위에 덧그리기 전에 미리 계산)
        if (dist(mouseX, mouseY, currentX, currentY) < tolerance && 
            !isAnyComboBoxExpanded() && mouseY > minY && mouseY < maxY) {
             hoverValue = currentValue;
             hoverIndex = i;
             hoverX = currentX;
             hoverY = currentY;
        }

        currentX += pointSpacing;
        lastDrawnValue = currentValue;
    }
    
    // 3. 점 그래프를 그립니다 (선 위에 덧그림).
    currentX = yAxisWidth; // X 좌표를 다시 시작 위치로 초기화
    lastDrawnValue = history.get(startIndex); // lastDrawnValue도 다시 초기화

    for (int i = startIndex; i < endIndex; i++) {
        int currentValue = history.get(i);
        
        // 튀는 값/일반 값에 따라 점 색상 결정
        if (abs(currentValue - lastDrawnValue) > kNoiseThreshold) {
            fill(255, 0, 0); // Red (튀는 값)
        } else {
            fill(0, 255, 0); // Green (일반 값)
        }
        
        int currentY = (int) map(currentValue, 0, maxADC, maxY, minY);
        
        // 점(원) 그리기
        noStroke(); // 점 테두리 제거
        ellipse(currentX, currentY, pointDiameter, pointDiameter);
        
        currentX += pointSpacing;
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
      
      // 데이터 값과 현재 시간(밀리초) 저장
      history.add(inValue);
      historyTime.add(millis());
      
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
```
