; Balance robot controller written in lisp

(define pos-x (lambda ()
    (* 0.5 (+
        (progn (select-motor 1) (get-dist))
        (progn (select-motor 2) (get-dist))
))))

(define pitch-set 0)
(define yaw-set (* (ix 2 (get-imu-rpy)) 57.29577951308232))
(define pos-set (pos-x))

(define was-running 0)
(define t-last (systime))
(define pos-last (pos-x))

(define kp 0.014)
(define kd 0.0016)

(define p-kp 50.0)
(define p-kd -33.0)

(define y-kp 0.003)
(define y-kd 0.0003)

(define enable-pos 1)
(define enable-yaw 1)

; This is received from the QML-program which acts as a remote control for the robot
(define proc-data (lambda (data)
    (progn
        (define enable-pos (ix 4 data))
        (define enable-yaw (ix 5 data))
        
        (if (= enable-pos 1)
            (progn
                (define pos-set (+ pos-set (* (ix 0 data) 0.002)))
                (define pos-set (- pos-set (* (ix 1 data) 0.002)))
        ) nil)
        
        (if (= enable-yaw 1)
            (progn
                (define yaw-set (- yaw-set (* (ix 2 data) 0.5)))
                (define yaw-set (+ yaw-set (* (ix 3 data) 0.5)))
        ) nil)
        
        (if (> yaw-set 360) (define yaw-set (- yaw-set 360)) nil)
        (if (< yaw-set 0) (define yaw-set (+ yaw-set 360)) nil)
)))

(define event-handler (lambda ()
    (progn
        (recv ((signal-data-rx . (? data)) (proc-data data))
              (_ nil))
        (event-handler)
)))

(event-register-handler (spawn event-handler))
(event-enable "event-data-rx")

(define abs (lambda (x) (if (> x 0) x (- x))))

(define set-output (lambda (left right)
    (progn
        (select-motor 1)
        (set-current-rel right)
        (select-motor 2)
        (set-current-rel left)
        (timeout-reset)
)))

(define speed-x (lambda ()
    (* 0.5 (+
        (progn (select-motor 1) (get-speed))
        (progn (select-motor 2) (get-speed))
))))

(define f (lambda ()
    (progn
        (define pitch (* (ix 1 (get-imu-rpy)) 57.29577951308232))
        (define yaw (* (ix 2 (get-imu-rpy)) 57.29577951308232))
        (define pitch-rate (ix 1 (get-imu-gyro)))
        (define yaw-rate (ix 2 (get-imu-gyro)))
        (define pos (+ (pos-x) (* pitch 0.00122))) ; Includes pitch compensation
        (define speed (speed-x))

        ; Loop rate measurement
        (define it-rate (/ 1 (secs-since t-last)))
        (define t-last (systime))
        
        (if (< (abs pitch) (if (= was-running 1) 45 10))
            (progn
                (define was-running 1)
                
                (if (= enable-pos 0) (define pos-set pos) nil)
                (if (= enable-yaw 0) (define yaw-set yaw) nil)
                
                (define pos-err (- pos-set pos))
                (define pitch-set (+ (* pos-err p-kp) (* speed p-kd)))
                
                (define yaw-err (- yaw-set yaw))
                (if (> yaw-err 180) (define yaw-err (- yaw-err 360)) nil)
                (if (< yaw-err -180) (define yaw-err (+ yaw-err 360)) nil)
                
                (define yaw-out (+ (* yaw-err y-kp) (* yaw-rate y-kd)))
                (define ctrl-out (+ (* kp (- pitch pitch-set)) (* kd pitch-rate)))
                
                (set-output (+ ctrl-out yaw-out) (- ctrl-out yaw-out))
            )
            
            (progn
                (define was-running 0)
                (set-output 0 0)
                (define pos-set pos)
                (define yaw-set yaw)
            )
        )
        
        (yield 1) ; Run as fast as possible
        (f)
)))

(if (< (systime) 50000) (yield 5000000) nil) ; Sleep after boot to wait for IMU to settle
(f)