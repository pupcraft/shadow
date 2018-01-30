(in-package :shadow)

(defclass layout ()
  ((%type :reader layout-type
          :initarg :type)
   (%size :accessor size)
   (%members :reader members
             :initform (make-hash-table))
   (%uniform :reader uniform
             :initarg :uniform)))

(defclass layout-member ()
  ((%dimensions :reader dimensions
                :initarg :dimensions
                :initform 1)
   (%element-count :reader element-count
                   :initarg :count
                   :initform 1)
   (%element-type :reader element-type
                  :initarg :element-type)
   (%stride :reader stride
            :initarg :stride)
   (%offset :reader offset
            :initarg :offset)
   (%size :reader size
          :initarg :size)))

(defun layout-struct-p (struct)
  (or (has-qualifier-p struct :ubo)
      (has-qualifier-p struct :ssbo)))

(defun get-layout-type (struct)
  (if (has-qualifier-p struct :std-430)
      :std430
      :std140))

(defun collect-layout-structs (layout)
  (let ((structs))
    (labels ((process (type)
               (typecase type
                 (varjo:v-array (process-array type))
                 (varjo:v-user-struct (process-struct type))))
             (process-array (type)
               (process (varjo:v-element-type type)))
             (process-struct (type)
               (unless (find type structs :test #'varjo:v-type-eq)
                 (map nil (lambda (x) (process (second x))) (varjo.internals:v-slots type))
                 (push type structs)))
             (find-structs (types)
               (map nil #'process types)
               (reverse structs)))
      (find-structs
       (loop :with struct = (varjo:v-type-of (uniform layout))
             :for (nil slot-type) :in (varjo.internals:v-slots struct)
             :when (typep slot-type 'varjo:v-user-struct)
               :collect slot-type)))))

(defun make-layout-member (layout data)
  (dolist (part (getf data :members))
    (destructuring-bind (&key type name offset size stride matrix-stride &allow-other-keys) part
      (alexandria:when-let ((unpacked-type (unpack-type type))
                            (path (ensure-keyword
                                   (format nil "~{~a~^.~}" (alexandria:ensure-list name)))))
        (setf (gethash path (members layout))
              (apply #'make-instance 'layout-member
                     :offset offset
                     :size size
                     :stride (or stride matrix-stride size)
                     unpacked-type))))))

(defun make-layout (uniform)
  (loop :with type = (get-layout-type (varjo:v-type-of uniform))
        :with layout = (make-instance 'layout :type type :uniform uniform)
        :for ((root) . (data)) :in (pack-layout layout)
        :when (eq root (varjo:name uniform))
          :do (make-layout-member layout data)
              (setf (size layout) (getf data :size))
        :finally (return layout)))

(defun collect-layouts (stage)
  (loop :for uniform :in (varjo:uniform-variables stage)
        :for struct = (varjo:v-type-of uniform)
        :when (layout-struct-p struct)
          :collect (make-layout uniform)))
